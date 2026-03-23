//
//  ClosedRange+Interpolated.swift
//  ClosedRange+Interpolated
//
//  Created by Alex Robinson on 7/8/21.
//

import Foundation

extension ClosedRange where Bound: FloatingPoint {

    func interpolatedValue(at position: Bound) -> Bound {
        lowerBound + (upperBound - lowerBound) * position
    }

}
