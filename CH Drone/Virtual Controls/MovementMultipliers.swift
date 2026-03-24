//
//  MovementMultipliers.swift
//  CH Drone
//
//  Created by Alex Robinson on 28/1/2022.
//

import Combine
import Foundation
import Logging

private let logger = Logger(label: "MovementMultipliers")

final class MovementMultipliers {

    let persistence: UserDefaults
    let key: String

    var didChangePublisher: AnyPublisher<Void, Never> { didChangePassthroughSubject.eraseToAnyPublisher() }

    // MARK: - Levels

    var pitch: MultiplierLevel {
        get { storage.pitch }
        set { storage.pitch = newValue }
    }

    var roll: MultiplierLevel {
        get { storage.roll }
        set { storage.roll = newValue }
    }

    var yaw: MultiplierLevel {
        get { storage.yaw }
        set { storage.yaw = newValue }
    }

    var verticalThrottle: MultiplierLevel {
        get { storage.verticalThrottle }
        set { storage.verticalThrottle = newValue }
    }

    // MARK: - Multipliers

    var pitchValue: Float { pitch.value(userDefaults: persistence) }
    var rollValue: Float { roll.value(userDefaults: persistence) }
    var yawValue: Float { yaw.value(userDefaults: persistence) }
    var verticalThrottleValue: Float { verticalThrottle.value(userDefaults: persistence) }

    init(persistence: UserDefaults, key: String) {
        self.persistence = persistence
        self.key = key

        if let persistenceData = persistence.data(forKey: key) {
            do {
                storage = try JSONDecoder().decode(Storage.self, from: persistenceData)
            } catch {
                logger.error("Failed to decode persisted movement multipliers")
                storage = .empty
            }
        } else {
            storage = .empty
        }
    }

    // MARK: - Private

    private let didChangePassthroughSubject = PassthroughSubject<Void, Never>()

    private var storage: Storage {
        didSet {
            persist()
            didChangePassthroughSubject.send()
        }
    }

    private func persist() {
        let storageData: Data?
        do {
            storageData = try JSONEncoder().encode(storage)
        } catch {
            logger.error("Failed to encode movement multipliers")
            storageData = nil
        }
        persistence.set(storageData, forKey: key)
    }

}

extension MovementMultipliers {

    struct Storage: Codable {
        static let empty = Storage(pitch: .medium, roll: .medium, yaw: .medium, verticalThrottle: .medium)

        var pitch: MultiplierLevel
        var roll: MultiplierLevel
        var yaw: MultiplierLevel
        var verticalThrottle: MultiplierLevel
    }

}

private extension MultiplierLevel {

    func value(userDefaults: UserDefaults) -> Float {
        switch self {
        case .slowest:
            return userDefaults.slowestMultiplier
        case .slow:
            return userDefaults.slowMultiplier
        case .medium:
            return userDefaults.mediumMultiplier
        case .fast:
            return userDefaults.fastMultiplier
        case .fastest:
            return userDefaults.fastestMultiplier
        }
    }

}
