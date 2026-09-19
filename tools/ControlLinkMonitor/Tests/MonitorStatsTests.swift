//
//  MonitorStatsTests.swift
//  Control Link Monitor
//

import XCTest

@testable import ControlLinkMonitor

final class MonitorStatsTests: XCTestCase {

    private func stick(_ seq: UInt64, session: String = "A", t: UInt64 = 0) -> ControlLinkStick {
        ControlLinkStick(session: session, seq: seq, t: t, pitch: 0.5, roll: 0, yaw: 0, throttle: 0, active: true, source: "simulator")
    }

    private func record(_ stats: inout MonitorStats, _ seqs: [UInt64], session: String = "A") {
        for (index, seq) in seqs.enumerated() {
            stats.recordStick(stick(seq, session: session), receivedAtWallMillis: 0, receivedAtMonotonic: Double(index) / 10)
        }
    }

    func testGapsInSequenceCountAsDropped() {
        var stats = MonitorStats()
        record(&stats, [1, 2, 3, 6, 7, 10])
        XCTAssertEqual(stats.received, 6)
        XCTAssertEqual(stats.dropped, 4)
        XCTAssertEqual(stats.droppedFraction, 0.4, accuracy: 1e-9)
    }

    func testOlderMessagesAreOutOfOrderAndNotShown() {
        var stats = MonitorStats()
        record(&stats, [1, 2, 5, 3, 6])
        XCTAssertEqual(stats.outOfOrder, 1)
        XCTAssertEqual(stats.dropped, 2)
        XCTAssertEqual(stats.lastStick?.seq, 6)
    }

    /// A new session restarts `seq` at 1, which must not count as thousands of drops or as
    /// out of order.
    func testNewSessionIsARestartNotAGap() {
        var stats = MonitorStats()
        record(&stats, [100, 101, 102], session: "A")
        record(&stats, [1, 2], session: "B")
        XCTAssertEqual(stats.restarts, 1)
        XCTAssertEqual(stats.dropped, 0)
        XCTAssertEqual(stats.outOfOrder, 0)
        XCTAssertEqual(stats.received, 5)
    }

    func testRateAndStaleness() {
        var stats = MonitorStats()
        record(&stats, Array(1...30)) // 10 Hz for 3 s, monotonic 0.0…2.9

        XCTAssertEqual(stats.rate(nowMonotonic: 2.95), 10, accuracy: 0.01) // 1.0…2.9 is the last 2 s
        XCTAssertFalse(stats.isStale(nowMonotonic: 3.1))
        XCTAssertTrue(stats.isStale(nowMonotonic: 3.25))
        XCTAssertEqual(stats.jitterMillis ?? -1, 0, accuracy: 1e-6)
    }

    func testSummaryStatistics() throws {
        let summary = try XCTUnwrap(MonitorStats.Summary([5, 1, 4, 2, 3]))
        XCTAssertEqual(summary.min, 1)
        XCTAssertEqual(summary.max, 5)
        XCTAssertEqual(summary.median, 3)
        XCTAssertEqual(summary.last, 3)
        XCTAssertEqual(summary.p95, 5)
        XCTAssertEqual(MonitorStats.Summary([1, 2, 3, 4])?.median, 2.5)
        XCTAssertNil(MonitorStats.Summary([]))
    }

    /// The iPad's clock runs 250 ms ahead of the Mac's. The link takes 10 ms each way, and one
    /// ping is delayed on the way back. The offset must come from the clean round trip, and a
    /// stick message must then measure 10 ms, not 260.
    func testClockOffsetFromShortestRoundTripCorrectsOneWayLatency() {
        var stats = MonitorStats()

        // Clean: sent at 1_000, iPad receives at Mac 1_010 = iPad 1_260, back at 1_020.
        stats.recordPong(ControlLinkPong(id: 1, from: "m", by: "ipad", t: 1_000, rt: 1_260), roundTripMillis: 20, sentAtWallMillis: 1_000)
        // Delayed return: same outbound leg, 60 ms back.
        stats.recordPong(ControlLinkPong(id: 2, from: "m", by: "ipad", t: 2_000, rt: 2_260), roundTripMillis: 70, sentAtWallMillis: 2_000)

        XCTAssertEqual(stats.clockOffset(for: "ipad") ?? .nan, 250, accuracy: 1e-9)
        XCTAssertEqual(stats.roundTrip(for: "ipad")?.median, 45)

        // Sent at iPad 3_250 (Mac 3_000), arrives at Mac 3_010.
        stats.recordStick(stick(1, t: 3_250), receivedAtWallMillis: 3_010, receivedAtMonotonic: 0)
        XCTAssertEqual(stats.oneWay?.last ?? .nan, 10, accuracy: 1e-9)
    }

    func testOneWayWaitsForAClockOffset() {
        var stats = MonitorStats()
        record(&stats, [1, 2, 3])
        XCTAssertNil(stats.oneWay)
    }

    func testResetClearsEverything() {
        var stats = MonitorStats()
        record(&stats, [1, 3])
        stats.recordPingSent()
        stats.reset()
        XCTAssertEqual(stats.received, 0)
        XCTAssertEqual(stats.dropped, 0)
        XCTAssertEqual(stats.pingsSent, 0)
        XCTAssertNil(stats.lastStick)
    }

}
