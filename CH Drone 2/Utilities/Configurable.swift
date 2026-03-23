//
//  Configurable.swift
//  CH Drone
//
//  Created by Alex Robinson on 13/1/2022.
//

import Foundation

protocol Configurable: AnyObject {}

extension Configurable {

    @discardableResult
    func configure(_ configure: (Self) -> Void) -> Self {
        configure(self)
        return self
    }

    @discardableResult
    func assigning<Value>(_ keyPath: ReferenceWritableKeyPath<Self, Value>, to value: Value) -> Self {
        self[keyPath: keyPath] = value
        return self
    }

}

extension NSObject: Configurable {}
