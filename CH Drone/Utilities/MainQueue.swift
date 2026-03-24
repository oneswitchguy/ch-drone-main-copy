//
//  MainQueue.swift
//
//  Created by Alex Robinson on 30/11/2022.
//  Copyright © 2022 Astrocode Pty Ltd. All rights reserved.
//

import Combine
import Foundation
import Logging
import os

/// Scheduler for putting things on the main queue quickly.
final class MainQueue: Scheduler {

    static let shared = MainQueue()

    typealias SchedulerTimeType = DispatchQueue.SchedulerTimeType
    typealias SchedulerOptions = DispatchQueue.SchedulerOptions

    var now: DispatchQueue.SchedulerTimeType { underlying.now }
    var minimumTolerance: DispatchQueue.SchedulerTimeType.Stride { underlying.minimumTolerance }

    func schedule(options: DispatchQueue.SchedulerOptions?, _ action: @escaping () -> Void) {
        underlying.schedule(options: options, { DispatchQueue.main(action) })
    }

    func schedule(after date: DispatchQueue.SchedulerTimeType, tolerance: DispatchQueue.SchedulerTimeType.Stride, options: DispatchQueue.SchedulerOptions?, _ action: @escaping () -> Void) {
        underlying.schedule(after: date, tolerance: tolerance, options: options, { DispatchQueue.main(action) })
    }

    func schedule(after date: DispatchQueue.SchedulerTimeType, interval: DispatchQueue.SchedulerTimeType.Stride, tolerance: DispatchQueue.SchedulerTimeType.Stride, options: DispatchQueue.SchedulerOptions?, _ action: @escaping () -> Void) -> Cancellable {
        underlying.schedule(after: date, interval: interval, tolerance: tolerance, options: options, { DispatchQueue.main(action) })
    }

    // MARK: - Private

    private let underlying = DispatchQueue.main

    private init() {}

}

// MARK: - Private extensions

private let logger = Logger(label: "mainQueue")

private extension DispatchQueue {

    /// Safely do things on the main queue.
    ///
    /// Reference: http://blog.benjamin-encz.de/post/main-queue-vs-main-thread/
    static func main(_ work: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: Globals.mainQueueKey) == Globals.mainQueueValue {
            // already on main queue; just do it.
            work()
        } else if Thread.isMainThread {
            // On the main thread but not the main queue.
            //
            // I wanted to use `DispatchQueue.main.sync` here, but it results in:
            //     BUG IN CLIENT OF LIBDISPATCH: dispatch_sync called on queue already owned by current thread
            //
            // Since the whole point of this exercise is to make sure work runs on the main **queue**,
            // this has to go through asynchronously for this one specific edge case.
            logger.warning("On main thread but not main queue; work will be run asynchronously")
            DispatchQueue.main.async(execute: work)
        } else {
            // run `sync` on main knowing that we're on a different queue and a different thread.
            DispatchQueue.main.sync(execute: work)
        }
    }

}

// MARK: - Private Globals

private struct DispatchSpecificValue: Hashable {}

private enum Globals {
    // Main queue is tagged when this key is initialized.
    static let mainQueueKey: DispatchSpecificKey<DispatchSpecificValue> = {
        let mainQueueKey = DispatchSpecificKey<DispatchSpecificValue>()
        DispatchQueue.main.setSpecific(key: mainQueueKey, value: mainQueueValue)
        return mainQueueKey
    }()

    static let mainQueueValue = DispatchSpecificValue()
}
