//
//  TelemetryLogger.swift
//  CH Drone
//
//  Created by Alex Robinson on 29/6/2022.
//  Copyright © 2022 Astrocode Pty Ltd. All rights reserved.
//

import Combine
import DJIUXSDKBeta
import Foundation
import Logging

private let logger = Logger(label: "telemetry")

final class TelemetryLogger {

    let joystickCommands: JoystickCommands
    let movementMultipliers: MovementMultipliers

    let motorsModel = StartStopMotorsWidgetModel()
    let altitude = DUXBetaAltitudeWidgetModel()
    let horizontalVelocity = DUXBetaHorizontalVelocityWidgetModel()
    let verticalVelocity = DUXBetaVerticalVelocityWidgetModel()
    let compass = DUXBetaCompassWidgetModel()
    let location = DUXBetaLocationWidgetModel()
    let battery = DUXBetaBatteryWidgetModel()

    let dateBuilder: () -> Date
    let directory: URL

    var widgetModels: [DUXBetaBaseWidgetModel] {
        [
            motorsModel,
            altitude,
            horizontalVelocity,
            verticalVelocity,
            compass,
            location,
            battery,
        ]
    }

    init(joystickCommands: JoystickCommands, movementMultipliers: MovementMultipliers, dateBuilder: @escaping () -> Date = Date.init, directory: URL = FileManager.default.documentsDirectory!) {
        self.joystickCommands = joystickCommands
        self.movementMultipliers = movementMultipliers
        self.dateBuilder = dateBuilder
        self.directory = directory

        widgetModels.forEach {
            $0.setup()
        }

        motorsCancellable = motorsModel.publisher(for: \.areMotorsOn)
            .removeDuplicates()
            .receiveOnMain()
            .sink { [weak self] areMotorsOn in
                if areMotorsOn {
                    self?.start()
                } else {
                    self?.end()
                }
            }

        joystickAssignmentCancellable = joystickCommands.$horizontalAxis.merge(with: joystickCommands.$verticalAxis)
            .removeDuplicates()
            .dropFirst()
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .receiveOnMain()
            .replaceOutputWithVoid()
            .sink { [weak self] in
                self?.logEvent(source: .joystickAssignmentChanged)
            }

        movementMultipliersCancellable = movementMultipliers.didChangePublisher
            .map {
                PitchRollYawThrottleMultiplierLevels(movementMultipliers.pitch, movementMultipliers.roll, movementMultipliers.yaw, movementMultipliers.verticalThrottle)
            }
            .removeDuplicates()
            .receiveOnMain()
            .replaceOutputWithVoid()
            .sink { [weak self] in
                self?.logEvent(source: .speedConfigurationChanged)
            }
    }

    deinit {
        widgetModels.forEach {
            $0.cleanup()
        }
    }

    func start() {
        guard !isRunning else {
            return
        }

        isRunning = true
        logEvent(source: .motorStarted)

        inFlightTimerCancellable = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.logFlightEvent()
            }
    }

    func end() {
        guard isRunning else {
            return
        }

        inFlightTimerCancellable = nil
        logEvent(source: .motorStopped)
        isRunning = false
    }

    func logFlightEvent() {
        logEvent(source: .inFlight)
    }

    func logEvent(source: TelemetryEvent.EventSource) {
        guard isRunning else {
            return
        }

        do {
            let event = makeEventForCurrentState(source: source)
            let data = Data(event.csvColumns.makeCSVRow().utf8)
            try logFileHandle?.write(contentsOf: data)
            try logFileHandle?.synchronize()
        } catch {
            logger.error("Failed to log event", metadata: ["error": .string("\(error)")])
        }
    }

    // MARK: - Private

    private var motorsCancellable: AnyCancellable?
    private var joystickAssignmentCancellable: AnyCancellable?
    private var movementMultipliersCancellable: AnyCancellable?
    private var inFlightTimerCancellable: AnyCancellable?

    private var joystickConfiguration: JoystickConfiguration { JoystickConfiguration(xAxis: joystickCommands.horizontalAxis, yAxis: joystickCommands.verticalAxis) }
    private var speedConfiguration: SpeedConfiguration { SpeedConfiguration(movementMultipliers: movementMultipliers) }

    private let fileManager: FileManager = .default

    private var logFileURL: URL?
    private var logFileHandle: FileHandle?

    private var isRunning: Bool {
        get { logFileURL != nil }
        set {
            do {
                if newValue {
                    let logFileURL = makeLogFileURL()
                    self.logFileURL = logFileURL
                    try createLogFile()
                } else {
                    try? closeLogFile()
                    logFileURL = nil
                }
            } catch {
                logger.error("Failed to set up log file", metadata: ["error": .string("\(error)")])
            }
        }
    }

    private let fileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    private func makeLogFileURL() -> URL {
        directory.appendingPathComponent(fileTimestampFormatter.string(from: dateBuilder())).appendingPathExtension("csv")
    }

    private func createLogFile() throws {
        guard let logFileURL = logFileURL else {
            return
        }

        guard !fileManager.fileExists(atPath: logFileURL.path) else {
            return
        }

        let data = Data(TelemetryEvent.csvHeadingColumns.makeCSVRow().utf8)

        try fileManager.createDirectory(at: logFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        fileManager.createFile(atPath: logFileURL.path, contents: nil)

        logFileHandle = try FileHandle(forWritingTo: logFileURL)
        try logFileHandle?.write(contentsOf: data)
    }

    private func closeLogFile() throws {
        try logFileHandle?.close()
        logFileHandle = nil
    }

    private func makeEventForCurrentState(source: TelemetryEvent.EventSource) -> TelemetryEvent {
        TelemetryEvent(
            timestamp: dateBuilder(),
            eventSource: source,
            altitudeAboveGroundLevel: altitude.altitudeState.altitudeAGL.meters,
            altitudeAboveMeanSeaLevel: altitude.altitudeState.altitudeAMSL.meters,
            downwardVelocity: verticalVelocity.verticalVelocityState.downwardVelocity.meters,
            upwardVelocity: verticalVelocity.verticalVelocityState.upwardVelocity.meters,
            horizontalVelocity: horizontalVelocity.horizontalVelocityState.currentVelocity.meters,
            heading: compass.deviceHeading,
            aircraftGPSCoordinates: LatLon(location.locationState.currentLocation),
            batteryPercentage: battery.batteryState.batteryPercentage,
            speedConfiguration: speedConfiguration,
            joystickConfiguration: joystickConfiguration
        )
    }

}

// MARK: - Helper Types

struct TelemetryEvent: Encodable {

    static let csvHeadingColumns: [String] = [
        "timestamp",
        "eventSource",
        "altitudeAboveGroundLevel",
        "altitudeAboveMeanSeaLevel",
        "downwardVelocity",
        "upwardVelocity",
        "horizontalVelocity",
        "heading",

        "aircraftCoordinates.lon",
        "aircraftCoordinates.lat",

        "batteryPercentage",

        "speedConfiguration.throttle",
        "speedConfiguration.pitch",
        "speedConfiguration.roll",
        "speedConfiguration.yaw",

        "joystickConfiguration.x",
        "joystickConfiguration.y",
    ]

    var csvColumns: [String] {
        [
            String.descriptionUnlessNil(timestamp),
            String.descriptionUnlessNil(eventSource),
            String.descriptionUnlessNil(altitudeAboveGroundLevel),
            String.descriptionUnlessNil(altitudeAboveMeanSeaLevel),
            String.descriptionUnlessNil(downwardVelocity),
            String.descriptionUnlessNil(upwardVelocity),
            String.descriptionUnlessNil(horizontalVelocity),
            String.descriptionUnlessNil(heading),

            String.descriptionUnlessNil(aircraftGPSCoordinates.longitude),
            String.descriptionUnlessNil(aircraftGPSCoordinates.latitude),

            String.descriptionUnlessNil(batteryPercentage),

            String.descriptionUnlessNil(speedConfiguration.throttle),
            String.descriptionUnlessNil(speedConfiguration.pitch),
            String.descriptionUnlessNil(speedConfiguration.roll),
            String.descriptionUnlessNil(speedConfiguration.yaw),

            String.descriptionUnlessNil(joystickConfiguration.xAxis),
            String.descriptionUnlessNil(joystickConfiguration.yAxis),
        ]
    }

    enum EventSource: String, Encodable {
        case initial
        case motorStarted
        case inFlight
        case motorStopped
        case speedConfigurationChanged
        case joystickAssignmentChanged
    }

    var timestamp: Date
    var eventSource: EventSource
    var altitudeAboveGroundLevel: Double
    var altitudeAboveMeanSeaLevel: Double
    var downwardVelocity: Double
    var upwardVelocity: Double
    var horizontalVelocity: Double
    var heading: CLLocationDirection
    var aircraftGPSCoordinates: LatLon
    var batteryPercentage: Float

    var speedConfiguration: SpeedConfiguration
    var joystickConfiguration: JoystickConfiguration
}

struct LatLon: Encodable {
    var latitude: Double
    var longitude: Double

    init(_ clLocationCoordinate2D: CLLocationCoordinate2D) {
        self.latitude = clLocationCoordinate2D.latitude
        self.longitude = clLocationCoordinate2D.longitude
    }
}

struct SpeedConfiguration: Encodable {
    var throttle: MultiplierLevel
    var pitch: MultiplierLevel
    var roll: MultiplierLevel
    var yaw: MultiplierLevel

    init(movementMultipliers: MovementMultipliers) {
        throttle = movementMultipliers.verticalThrottle
        pitch = movementMultipliers.pitch
        roll = movementMultipliers.roll
        yaw = movementMultipliers.yaw
    }
}

struct JoystickConfiguration: Encodable {
    var xAxis: JoystickCommands.AxisOption?
    var yAxis: JoystickCommands.AxisOption?
}


// MARK: - Private

private extension Measurement {
    var meters: Double {
        NSMeasurement(doubleValue: value, unit: unit).converting(to: UnitLength.meters).value
    }
}

private struct PitchRollYawThrottleMultiplierLevels: Equatable {
    let pitch: MultiplierLevel
    let roll: MultiplierLevel
    let yaw: MultiplierLevel
    let verticalThrottle: MultiplierLevel

    init(_ pitch: MultiplierLevel, _ roll: MultiplierLevel, _ yaw: MultiplierLevel, _ verticalThrottle: MultiplierLevel) {
        self.pitch = pitch
        self.roll = roll
        self.yaw = yaw
        self.verticalThrottle = verticalThrottle
    }
}
