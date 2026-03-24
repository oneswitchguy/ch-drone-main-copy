//
//  AsyncSetting.swift
//  AsyncSetting
//
//  Created by Alex Robinson on 5/8/21.
//

import Foundation

enum AsyncSetting<T> {
    case value(T)
    case pendingValue(oldValue: T, newValue: T)
    case failed(oldValue: T, newValue: T, error: Error)

    var value: T {
        switch self {
        case .value(let t): return t
        case .pendingValue(_, let t): return t
        case .failed(let t, _, _): return t
        }
    }

    var isPending: Bool {
        if case .pendingValue = self { return true } else { return false }
    }

    mutating func setValue(_ newValue: T) {
        self = .value(newValue)
    }

    mutating func setPendingValue(newValue: T) {
        self = .pendingValue(oldValue: value, newValue: newValue)
    }

    mutating func setFailed(failedValue: T, error: Error) {
        self = .failed(oldValue: value, newValue: failedValue, error: error)
    }
}
