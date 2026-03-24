//
//  ValueSubject.swift
//  DroneSwitchControl
//
//  Created by Alex Robinson on 1/8/21.
//

import Combine
import Foundation

/// A property wrapper similar to `@Published`, which publishes *after* a value has been set. Wraps a `CurrentValueSubject`.
@available(iOS 13.0, *)
@propertyWrapper
public struct ValueSubject<Value> {

    // A private-ish trick for disallowing direct property access except when this property wrapper is used on a reference type.
    // More info: https://www.swiftbysundell.com/articles/accessing-a-swift-property-wrappers-enclosing-instance/
    public static subscript<Enclosing>(_enclosingInstance instance: Enclosing, wrapped wrappedKeyPath: ReferenceWritableKeyPath<Enclosing, Value>, storage storageKeyPath: ReferenceWritableKeyPath<Enclosing, Self>) -> Value {
        get { instance[keyPath: storageKeyPath].projectedValue.innerSubject.value }
        set { instance[keyPath: storageKeyPath].projectedValue.innerSubject.value = newValue }
    }

    @available(*, unavailable, message: "@ValueSubject is only available on properties of classes")
    public var wrappedValue: Value {
        // swiftlint:disable:next fatal_error_message
        get { fatalError() }
        // swiftlint:disable:next fatal_error_message unused_setter_value
        set { fatalError() }
    }

    /// The value publisher. The `projectedValue` is the property accessed with the `$` prefix.
    public var projectedValue: Publisher {
        mutating get { publisher }
        set { publisher = newValue }
    }

    public var currentValue: Value {
        mutating get { projectedValue.innerSubject.value }
    }

    /// Creates the value subject instance with an initial wrapped value.
    ///
    /// Don't use this initializer directly. Instead, create a property with the `@ValueSubject` attribute, as shown here:
    ///
    ///     @ValueSubject var lastUpdated: Date = Date()
    ///
    /// - Parameter wrappedValue: The publisher's initial value.
    public init(wrappedValue: Value) {
        self.publisher = .init(initialValue: wrappedValue)
    }

    /// Creates the value subject instance with an initial value.
    ///
    /// - Parameter initialValue: The publisher's initial value.
    public init(initialValue: Value) {
        self.init(wrappedValue: initialValue)
    }

    // MARK: - Private

    /// The internal publisher, used for storage to allow a `mutating get` in `projectedValue`.
    private var publisher: Publisher

}

// MARK: - Publisher

@available(iOS 13.0, *)
extension ValueSubject {

    /// A publisher for properties marked with the `@ValueSubject` attribute.
    public struct Publisher: Combine.Publisher {

        public typealias Output = Value
        public typealias Failure = Never

        public func receive<S>(subscriber: S) where S: Subscriber, Failure == S.Failure, Output == S.Input {
            innerSubject.receive(subscriber: subscriber)
        }

        init(initialValue: Value) {
            self.innerSubject = .init(initialValue)
        }

        let innerSubject: CurrentValueSubject<Value, Never>

    }

}

// MARK: - Operators

@available(iOS 13.0, *)
extension Publisher where Self.Failure == Never {

    /// Republishes elements received from a publisher, by assigning them to a property marked as a `ValueSubject`.
    ///
    /// Use this operator when you want to receive elements from a publisher and republish them through a property marked with the `@ValueSubject` attribute. The `assign(to:)` operator manages the life cycle of the subscription, canceling the subscription automatically when the ``ValueSubject`` instance deinitializes. Because of this, the `assign(to:)` operator doesn't return an ``AnyCancellable`` that you're responsible for like ``assign(to:on:)`` does.
    ///
    /// - Parameter valueSubject: A property marked with the `@ValueSubject` attribute, which receives and republishes all elements received from the upstream publisher.
    public func assign(to valueSubject: inout ValueSubject<Self.Output>.Publisher) {
        subscribe(ValueSubjectSubscriber(subject: valueSubject.innerSubject))
    }

    /// Attaches the specified subject to this publisher.
    ///
    /// - Parameter valueSubject: The subject to attach to this publisher.
    public func subscribe(_ valueSubject: ValueSubject<Self.Output>.Publisher) -> AnyCancellable {
        subscribe(valueSubject.innerSubject)
    }

}

// MARK: - Private

@available(iOS 13.0, *)
private struct ValueSubjectSubscriber<Value>: Subscriber {

    typealias Input = Value
    typealias Failure = Never

    let combineIdentifier = CombineIdentifier()

    weak var subject: CurrentValueSubject<Value, Never>?

    func receive(subscription: Subscription) {
        subject?.send(subscription: subscription)
        subscription.request(.unlimited)
    }

    func receive(_ input: Value) -> Subscribers.Demand {
        subject?.send(input)
        return .none
    }

    func receive(completion: Subscribers.Completion<Never>) {
        subject?.send(completion: completion)
    }

}
