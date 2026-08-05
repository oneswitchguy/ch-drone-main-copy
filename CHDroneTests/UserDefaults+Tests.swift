//
//  UserDefaults+Tests.swift
//  CHDroneTests
//
//  Created by Alex Robinson on 10/6/2022.
//  Copyright © 2022 Astrocode Pty Ltd. All rights reserved.
//

import Foundation
@testable import CH_Drone_2

extension UserDefaults {

    static func makeTestDefaults() -> UserDefaults {
        let defaults = UserDefaults()
        defaults.registerSettingsDefaults()
        return defaults
    }

}
