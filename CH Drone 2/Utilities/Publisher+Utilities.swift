//
//  Publisher+Utilities.swift
//  Publisher+Utilities
//
//  Created by Alex Robinson on 5/8/21.
//

import Combine
import Foundation

extension Publisher where Failure == Never {
    func assign<Root: AnyObject>(to keyPath: ReferenceWritableKeyPath<Root, Output>, onWeak object: Root) -> AnyCancellable {
        sink { [weak object] output in
            object?[keyPath: keyPath] = output
        }
    }
}

extension Publisher {
    /// Receive on the main queue, avoiding a queue jump if the publisher was already on the main queue.
    func receiveOnMain() -> Publishers.ReceiveOn<Self, MainQueue> {
        receive(on: MainQueue.shared)
    }

    func replaceOutputWithVoid() -> Publishers.Map<Self, Void> {
        map { _ in }
    }
}
