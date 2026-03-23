//
//  MultiplierFormatter.swift
//  CH Drone
//
//  Created by Alex Robinson on 28/1/2022.
//

import Foundation

let multiplierFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.maximumFractionDigits = 2
    return formatter
}()
