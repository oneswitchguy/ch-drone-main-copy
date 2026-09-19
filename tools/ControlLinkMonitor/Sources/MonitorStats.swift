//
//  MonitorStats.swift
//  Control Link Monitor
//

import Foundation

/// Everything the monitor measures, kept apart from MQTT and SwiftUI so it can be tested.
///
/// Times come in two kinds, and the difference matters:
/// - **Monotonic** seconds (`DispatchTime`), for anything measured on this Mac alone: round
///   trips, message rate and jitter. The wall clock can be stepped by NTP mid-run.
/// - **Wall-clock** milliseconds since 1970, for anything compared with another device's
///   `t` or `rt`, which is all the wire carries.
///
/// One-way latency needs the two clocks' offset. That is estimated from pings, using the
/// round trip with the shortest time: `offset = rt − (sent + rtt / 2)`, the responder's
/// clock minus this Mac's. The shortest round trip is the one least likely to have been
/// delayed unevenly between the two directions.
struct MonitorStats {

    struct Summary: Equatable {
        let last: Double
        let min: Double
        let median: Double
        let p95: Double
        let max: Double
        let count: Int

        init?(_ samples: [Double]) {
            guard let last = samples.last else { return nil }
            let sorted = samples.sorted()
            self.last = last
            self.min = sorted[0]
            self.max = sorted[sorted.count - 1]
            self.count = sorted.count
            let middle = sorted.count / 2
            self.median = sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
            self.p95 = sorted[Swift.max(0, Int((0.95 * Double(sorted.count)).rounded(.up)) - 1)]
        }
    }

    struct Responder: Equatable {
        var pongs = 0
        var roundTrips: [Double] = []
        /// The offset measured alongside the shortest round trip so far.
        var bestOffset: (roundTrip: Double, offset: Double)?

        static func == (lhs: Responder, rhs: Responder) -> Bool {
            lhs.pongs == rhs.pongs && lhs.roundTrips == rhs.roundTrips
                && lhs.bestOffset?.roundTrip == rhs.bestOffset?.roundTrip
                && lhs.bestOffset?.offset == rhs.bestOffset?.offset
        }
    }

    /// Past this gap between stick messages, the mover is required to return to neutral.
    static let staleAfterMillis: Double = 300
    /// How many recent samples each summary covers.
    static let window = 100

    private(set) var received = 0
    private(set) var dropped = 0
    private(set) var outOfOrder = 0
    /// Times the stick stream came back under a new session, which is an app restart.
    private(set) var restarts = 0
    private(set) var lastStick: ControlLinkStick?
    private(set) var pingsSent = 0
    private(set) var responders: [String: Responder] = [:]

    // MARK: - Recording

    mutating func recordStick(_ stick: ControlLinkStick, receivedAtWallMillis: Double, receivedAtMonotonic: Double) {
        if stick.session != lastStick?.session {
            if lastStick != nil {
                restarts += 1
            }
            lastSeq = stick.seq
        } else if stick.seq > lastSeq {
            dropped += Int(stick.seq - lastSeq - 1)
            lastSeq = stick.seq
        } else {
            // Older than one already seen. The mover would ignore it; so does the display.
            outOfOrder += 1
            return
        }

        received += 1
        lastStick = stick
        lastStickMonotonic = receivedAtMonotonic
        Self.append(receivedAtMonotonic, to: &arrivals)

        if let offset = clockOffset(for: "ipad") {
            Self.append(receivedAtWallMillis - (Double(stick.t) - offset), to: &oneWaySamples)
        }
    }

    mutating func recordPingSent() {
        pingsSent += 1
    }

    /// `roundTripMillis` is measured on this Mac's monotonic clock; `sentAtWallMillis` is the
    /// wall-clock time the ping went out, kept at full precision rather than `t`'s whole
    /// milliseconds.
    mutating func recordPong(_ pong: ControlLinkPong, roundTripMillis: Double, sentAtWallMillis: Double) {
        var responder = responders[pong.by] ?? Responder()
        responder.pongs += 1
        Self.append(roundTripMillis, to: &responder.roundTrips)

        let offset = Double(pong.rt) - (sentAtWallMillis + roundTripMillis / 2)
        if responder.bestOffset.map({ roundTripMillis < $0.roundTrip }) ?? true {
            responder.bestOffset = (roundTripMillis, offset)
        }
        responders[pong.by] = responder
    }

    mutating func reset() {
        self = MonitorStats()
    }

    // MARK: - Reading

    /// Stick messages per second over the last two seconds.
    func rate(nowMonotonic: Double) -> Double {
        let recent = arrivals.filter { nowMonotonic - $0 <= 2 }
        return Double(recent.count) / 2
    }

    /// Standard deviation of the gaps between stick messages, in milliseconds. At a steady
    /// 10 Hz this is near zero; Wi-Fi power saving shows up here first.
    var jitterMillis: Double? {
        guard arrivals.count >= 3 else { return nil }
        let gaps = zip(arrivals.dropFirst(), arrivals).map { ($0 - $1) * 1_000 }
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        let variance = gaps.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(gaps.count)
        return variance.squareRoot()
    }

    /// Milliseconds since the last stick message, or nil if none has arrived.
    func ageMillis(nowMonotonic: Double) -> Double? {
        lastStickMonotonic.map { (nowMonotonic - $0) * 1_000 }
    }

    func isStale(nowMonotonic: Double) -> Bool {
        ageMillis(nowMonotonic: nowMonotonic).map { $0 > Self.staleAfterMillis } ?? false
    }

    var droppedFraction: Double {
        let expected = received + dropped
        return expected == 0 ? 0 : Double(dropped) / Double(expected)
    }

    func roundTrip(for responder: String) -> Summary? {
        responders[responder].flatMap { Summary($0.roundTrips) }
    }

    /// The responder's clock minus this Mac's, in milliseconds.
    func clockOffset(for responder: String) -> Double? {
        responders[responder]?.bestOffset?.offset
    }

    /// iPad to this Mac, through the broker, corrected for the clock offset.
    var oneWay: Summary? {
        Summary(oneWaySamples)
    }

    /// Plain text for pasting into a message to the engineer.
    func report(nowMonotonic: Double, broker: String) -> String {
        func ms(_ value: Double) -> String { String(format: "%.1f ms", value) }
        func line(_ summary: Summary) -> String {
            "median \(ms(summary.median)), p95 \(ms(summary.p95)), min \(ms(summary.min)), max \(ms(summary.max)) over \(summary.count)"
        }

        var lines = ["Control link report, broker \(broker)"]
        lines.append(String(
            format: "Stick stream: %d received, %d dropped (%.1f%%), %d out of order, %.1f msg/s",
            received, dropped, droppedFraction * 100, outOfOrder, rate(nowMonotonic: nowMonotonic)
        ))
        if let jitterMillis {
            lines.append("Jitter between messages: \(ms(jitterMillis))")
        }
        for name in responders.keys.sorted() {
            guard let summary = roundTrip(for: name) else { continue }
            lines.append("Round trip to \(name): \(line(summary))")
            if let offset = clockOffset(for: name) {
                lines.append("  \(name) clock offset: \(ms(offset))")
            }
        }
        if let oneWay {
            lines.append("One way, iPad to Mac: \(line(oneWay))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private var lastSeq: UInt64 = 0
    private var lastStickMonotonic: Double?
    private var arrivals: [Double] = []
    private var oneWaySamples: [Double] = []

    private static func append(_ value: Double, to samples: inout [Double]) {
        samples.append(value)
        if samples.count > Self.window {
            samples.removeFirst(samples.count - Self.window)
        }
    }

}
