//
//  MonitorView.swift
//  Control Link Monitor
//

import SwiftUI

struct MonitorView: View {

    @ObservedObject var model: MonitorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                brokerSection
                appSection
                sticksSection
                streamSection
                latencySection
                HStack {
                    Button("Reset Statistics", action: model.resetStats)
                    Button("Copy Report", action: model.copyReport)
                        .help("Copies a plain-text summary for sending to the engineer")
                }
            }
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 560)
    }

    // MARK: - Broker

    private var brokerSection: some View {
        GroupBox("Broker") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Locked while connected: a change would only apply on the next connect.
                    Group {
                        TextField("Host", text: $model.host)
                            .accessibilityLabel("Broker host")
                        TextField("Port", text: $model.port)
                            .frame(width: 70)
                            .accessibilityLabel("Broker port")
                    }
                    .disabled(model.isRunning)
                    Button(model.isRunning ? "Disconnect" : "Connect", action: model.toggleConnection)
                        .keyboardShortcut(.defaultAction)
                }

                statusRow(brokerDescription, color: brokerColor)
            }
            .padding(4)
        }
    }

    private var brokerDescription: String {
        switch model.brokerState {
        case .idle: return "Not connected"
        case .connecting(let address): return "Connecting to \(address)…"
        case .connected(let address): return "Connected to \(address)"
        case .failed(let reason): return reason
        }
    }

    private var brokerColor: Color {
        switch model.brokerState {
        case .connected: return .green
        case .failed: return .orange
        case .idle, .connecting: return .secondary
        }
    }

    // MARK: - App

    private var appSection: some View {
        GroupBox("iPad app") {
            VStack(alignment: .leading, spacing: 4) {
                if let status = model.appStatus {
                    statusRow(status.online ? "Online" : "Offline", color: status.online ? .green : .red)
                    row("Device", status.device ?? "—")
                    row("Build", status.build ?? "—")
                    row("Session", String(status.session.prefix(8)))
                } else {
                    statusRow("No status yet — turn on Link in the app's simulator", color: .secondary)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Sticks

    private var sticksSection: some View {
        GroupBox("Sticks") {
            VStack(alignment: .leading, spacing: 6) {
                let stick = model.stats.lastStick
                stickBar("Pitch", stick?.pitch, positive: "forward", negative: "back")
                stickBar("Roll", stick?.roll, positive: "right", negative: "left")
                stickBar("Yaw", stick?.yaw, positive: "right", negative: "left")
                stickBar("Throttle", stick?.throttle, positive: "up", negative: "down")
                if let stick {
                    row("Source", "\(stick.source), \(stick.active ? "active" : "at rest")")
                }
            }
            .padding(4)
        }
    }

    private func stickBar(_ name: String, _ value: Float?, positive: String, negative: String) -> some View {
        let value = Double(value ?? 0)
        return HStack {
            Text(name).frame(width: 70, alignment: .leading)
            GeometryReader { geometry in
                let half = geometry.size.width / 2
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: abs(value) * half)
                        .offset(x: value >= 0 ? half : half - abs(value) * half)
                    Rectangle().fill(.secondary).frame(width: 1).offset(x: half)
                }
            }
            .frame(height: 10)
            Text(String(format: "%+.3f", value))
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(stickDescription(value, positive: positive, negative: negative))
    }

    private func stickDescription(_ value: Double, positive: String, negative: String) -> String {
        guard value != 0 else { return "centred" }
        return String(format: "%.0f percent %@", abs(value) * 100, value > 0 ? positive : negative)
    }

    // MARK: - Stream

    private var streamSection: some View {
        GroupBox("Stick stream") {
            VStack(alignment: .leading, spacing: 4) {
                let stats = model.stats
                let now = model.now
                row("Rate", String(format: "%.1f messages a second", stats.rate(nowMonotonic: now)))
                row("Received", "\(stats.received)")
                row("Dropped", String(format: "%d (%.1f%%)", stats.dropped, stats.droppedFraction * 100))
                row("Out of order", "\(stats.outOfOrder)")
                if stats.restarts > 0 {
                    row("App restarts", "\(stats.restarts)")
                }
                row("Jitter", stats.jitterMillis.map(milliseconds) ?? "—")
                if let age = stats.ageMillis(nowMonotonic: now) {
                    let stale = stats.isStale(nowMonotonic: now)
                    statusRow(
                        stale ? "Stale: last message \(milliseconds(age)) ago" : "Last message \(milliseconds(age)) ago",
                        color: stale ? .red : .green
                    )
                }
            }
            .padding(4)
        }
    }

    // MARK: - Latency

    private var latencySection: some View {
        GroupBox("Latency") {
            VStack(alignment: .leading, spacing: 8) {
                let stats = model.stats
                let responders = stats.responders.keys.sorted()

                if responders.isEmpty {
                    Text(stats.pingsSent == 0 ? "Pings start once connected" : "Waiting for a pong (\(stats.pingsSent) pings sent)")
                        .foregroundStyle(.secondary)
                }

                ForEach(responders, id: \.self) { name in
                    if let summary = stats.roundTrip(for: name) {
                        summaryBlock("Round trip to \(name)", summary)
                        if let offset = stats.clockOffset(for: name) {
                            row("\(name) clock offset", milliseconds(offset))
                        }
                    }
                }

                if let oneWay = stats.oneWay {
                    summaryBlock("One way, iPad to this Mac", oneWay)
                }
            }
            .padding(4)
        }
    }

    private func summaryBlock(_ title: String, _ summary: MonitorStats.Summary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            row("Median", milliseconds(summary.median))
            row("95th percentile", milliseconds(summary.p95))
            row("Best, worst", "\(milliseconds(summary.min)), \(milliseconds(summary.max))")
            row("Last", milliseconds(summary.last))
            row("Samples", "\(summary.count)")
        }
    }

    // MARK: - Rows

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private func statusRow(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }

    private func milliseconds(_ value: Double) -> String {
        String(format: "%.1f ms", value)
    }

}
