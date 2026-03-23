//
//  Array+CSV.swift
//  CH Drone
//
//  Created by Alex Robinson on 1/7/2022.
//  Copyright © 2022 Astrocode Pty Ltd. All rights reserved.
//

import Foundation

public extension Array where Element == String {
    func makeCSVRow(separator: String = ",", endOfLine: String = "\n") -> String {
        return map({ $0.csvEscaped(separator: separator) }).joined(separator: separator).appending(endOfLine)
    }
}

public extension CustomStringConvertible {
    func csvEscaped(separator: String) -> String {
        let doubleQuote = "\""
        let escaped = description.replacingOccurrences(of: doubleQuote, with: doubleQuote + doubleQuote)
        if escaped.count != description.count || escaped.contains(separator) {
            return doubleQuote + escaped + doubleQuote
        } else {
            return escaped
        }
    }
}
