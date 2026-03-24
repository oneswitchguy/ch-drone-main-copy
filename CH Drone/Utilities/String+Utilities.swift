//
//  String+Utilities.swift
//  CH Drone
//
//  Created by Alex Robinson on 1/7/2022.
//  Copyright © 2022 Astrocode Pty Ltd. All rights reserved.
//

import Foundation

extension String {

    static func descriptionUnlessNil<T>(_ wrapped: Optional<T>) -> String {
        if let unwrapped = wrapped {
            return String(describing: unwrapped)
        } else {
            return ""
        }
    }

    static func descriptionUnlessNil<Subject>(_ subject: Subject) -> String {
        return String(describing: subject)
    }

}
