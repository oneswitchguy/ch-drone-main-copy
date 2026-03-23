//
//  MultiplierLevel.swift
//  CH Drone
//
//  Created by Alex Robinson on 28/1/2022.
//

import Foundation

enum MultiplierLevel: String, CaseIterable, Codable {
    case slowest
    case slow
    case medium
    case fast
    case fastest

    var localizedName: String {
        switch self {
        case .slowest:
            return NSLocalizedString("Slowest", comment: "")
        case .slow:
            return NSLocalizedString("Slow", comment: "")
        case .medium:
            return NSLocalizedString("Medium", comment: "")
        case .fast:
            return NSLocalizedString("Fast", comment: "")
        case .fastest:
            return NSLocalizedString("Fastest", comment: "")
        }
    }
}
