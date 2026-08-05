//
//  ConnectionManager.swift
//  DroneSwitchControl
//
//  Created by Alex Robinson on 1/8/21.
//

import Foundation
import DJISDK
import Logging

private let logger = Logger(label: String(describing: ConnectionManager.self))

struct Config {
    static var skipConnection: Bool {
#if targetEnvironment(simulator)
        return true
#else
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "SkipConnection")
        #else
        return false
        #endif
#endif
    }

    static let simulatedRadar: ObstacleAvoiding? = {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "SimulateRadar") ? SimulatedObstacleAvoidance() : nil
        #else
        return nil
        #endif
    }()

    static let simulatedLandingAssistance: LandingAssisting? = {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "SimulateRadar") ? SimulatedLandingAssistance() : nil
        #else
        return nil
        #endif
    }()
}

final class SimulatorAircraft: DJIBaseProduct, Aircraft {
    var flightControl: FlightControlling?
    var obstacleAvoidance: ObstacleAvoiding?
    var landingAssistance: LandingAssisting?

    override var model: String? { "iOS Simulator Aircraft" }
}

final class ConnectionManager: NSObject, DJISDKManagerDelegate {

    // MARK: - Registration

    enum RegistrationState {
        case initial
        case registered
        case failed(Error)
    }

    @ValueSubject private(set) var registrationState: RegistrationState = .initial

    func register() {
        DJISDKManager.registerApp(with: self)
    }

    func appRegisteredWithError(_ error: Error?) {
        if let error = error {
            registrationState = .failed(error)
        } else {
            registrationState = .registered
        }
    }

    // MARK: - Database Download

    enum DatabaseDownloadState {
        case initial
        case changed(Progress)
    }

    @ValueSubject private(set) var downloadState: DatabaseDownloadState = .initial

    func didUpdateDatabaseDownloadProgress(_ progress: Progress) {
        logger.info("didUpdateDatabaseDownloadProgress", metadata: ["progress": .stringConvertible(progress)])
        downloadState = .changed(progress)
    }

    // MARK: - Product Connection

    enum ConnectionState {
        case initial
        case connecting
        case disconnected
        case unsupported(DJIBaseProduct)
        case connected(Aircraft)

        var isProductConnected: Bool {
            switch self {
            case .connected, .unsupported:
                return true
            case .initial, .connecting, .disconnected:
                return false
            }
        }

        var product: DJIBaseProduct? {
            switch self {
            case .connected(let product as DJIBaseProduct), .unsupported(let product):
                return product
            case .connected:
                // Some non-DJI project has connected. Probably a mock device.
                return nil
            case .initial, .connecting, .disconnected:
                return nil
            }
        }

    }

    @ValueSubject private(set) var connectionState: ConnectionState = .disconnected

    func connect() {
        if Config.skipConnection {
            let simulatorAircraft = SimulatorAircraft()
            simulatorAircraft.obstacleAvoidance = Config.simulatedRadar
            connectionState = .connected(simulatorAircraft)
            return
        }

        if DJISDKManager.startConnectionToProduct() {
            connectionState = .connecting
        } else {
            connectionState = .disconnected
        }
    }

    func disconnect() {
        DJISDKManager.stopConnectionToProduct()
    }

    func productConnected(_ product: DJIBaseProduct?) {
        logger.info("Product connected", metadata: ["description": .string(product?.description ?? "<none>")])
        updateConnectionState(product: product)
    }

    func productChanged(_ product: DJIBaseProduct?) {
        logger.info("Product changed", metadata: ["description": .string(product?.description ?? "<none>")])
        updateConnectionState(product: product)
    }

    func productDisconnected() {
        logger.info("Product disconnected")
        connectionState = .disconnected
    }

    func updateConnectionState(product: DJIBaseProduct?) {
        if let aircraft = product as? DJIAircraft {
            connectionState = .connected(aircraft)
        } else if let product = product {
            connectionState = .unsupported(product)
        } else {
            connectionState = .disconnected
        }
    }

}
