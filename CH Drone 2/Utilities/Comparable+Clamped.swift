//
//  Comparable+Clamped.swift
//  Comparable+Clamped
//
//  Created by Alex Robinson on 6/8/21.
//

import Foundation

public extension Comparable {

    func clamped(min: Self, max: Self) -> Self {
        Swift.min(Swift.max(self, min), max)
    }

    func clamped(to range: ClosedRange<Self>) -> Self {
        clamped(min: range.lowerBound, max: range.upperBound)
    }

}
