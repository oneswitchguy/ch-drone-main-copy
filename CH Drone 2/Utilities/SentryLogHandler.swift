/*
 MIT License

 Copyright (c) 2022 Eric Lewis.

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
 DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
 OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE
 OR OTHER DEALINGS IN THE SOFTWARE.
 */

// https://github.com/ericlewis/swift-log-sentry

import Foundation
import Logging
import Sentry

public struct SentryLogHandler: LogHandler {
    private let label: String
    private let client: SentryClient

    public var metadata = Logger.Metadata()
    public var logLevel: Logger.Level = .info

    public init(label: String, client: SentryClient = .live) {
        self.label = label
        self.client = client
    }

    public func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
        let crumb = Breadcrumb()

        crumb.category = label

        switch level {
        case .critical:
            crumb.level = .fatal
        case .debug:
            crumb.level = .debug
        case .info:
            crumb.level = .info
        case .notice:
            crumb.level = .warning
        case .warning:
            crumb.level = .warning
        case .trace:
            crumb.level = .debug
        case .error:
            crumb.level = .error
        }

        crumb.type = "log"
        crumb.message = message.description
        crumb.timestamp = Date()

        crumb.data = (metadata ?? self.metadata).reduce(into: [:]) { data, metadata in
            data[metadata.key] = metadata.value.description
        }

        crumb.data?["file"] = file
        crumb.data?["function"] = function
        crumb.data?["line"] = line

        client.addBreadcrumb(crumb)
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { self.metadata[key] }
        set { self.metadata[key] = newValue }
    }
}

// MARK: - SentryClient

public struct SentryClient {
    public var addBreadcrumb: (_ crumb: Breadcrumb) -> Void

    public init(addBreadcrumb: @escaping (_ crumb: Breadcrumb) -> Void) {
        self.addBreadcrumb = addBreadcrumb
    }
}

// MARK: - SentryClient+Live

extension SentryClient {
    public static let live = SentryClient { crumb in
        SentrySDK.addBreadcrumb(crumb)
    }
}
