//
//  FileManager+Utilities.swift
//  CH Drone
//
//  Created by Alex Robinson on 30/6/2022.
//  Copyright © 2022 Astrocode Pty Ltd. All rights reserved.
//

import Foundation

extension FileManager {
    var documentsDirectory: URL? {
        urls(for: .documentDirectory, in: .userDomainMask).first
    }
}
