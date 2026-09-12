//
//  NWPathMonitor+AsyncStream.swift
//  LabsPlatformSwift
//

import Network

extension NWPathMonitor {
    /// Starts the monitor and yields every path update until the stream is cancelled.
    func paths() -> AsyncStream<NWPath> {
        AsyncStream { continuation in
            pathUpdateHandler = { continuation.yield($0) }
            continuation.onTermination = { _ in self.cancel() }
            start(queue: DispatchQueue(label: "org.pennlabs.platform.reachability", qos: .utility))
        }
    }
}
