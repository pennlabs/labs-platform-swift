//
//  LabsAnalytics.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation
import SwiftUI
import SwiftData

public extension LabsPlatform {
    final actor Analytics: Sendable, ModelActor {
        public let modelContainer: ModelContainer
        public let modelExecutor: any ModelExecutor

        public struct Configuration: Sendable {
            let endpoint: URL
            let pushInterval: TimeInterval
            let expireInterval: TimeInterval
            let bufferInterval: TimeInterval

            public init(endpoint: URL = URL(string: "https://analytics.pennlabs.org/analytics/")!,
                        pushInterval: TimeInterval = 30,
                        expireInterval: TimeInterval = TimeInterval(60 * 60 * 24 * 7),
                        bufferInterval: TimeInterval = 5) {
                self.endpoint = endpoint
                self.pushInterval = pushInterval
                self.expireInterval = expireInterval
                self.bufferInterval = bufferInterval
            }
        }

        private var activeOperations: [AnalyticsTimedOperation] = []
        private var isSubmitting = false

        let configuration: Analytics.Configuration

        init?(configuration: Analytics.Configuration? = Analytics.Configuration()) throws {
            guard let configuration else { return nil }

            self.modelContainer = try ModelContainer(for: AnalyticsTxn.self)
            self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
            self.configuration = configuration

            let context = modelExecutor.modelContext
            let expired = try context.fetch(AnalyticsTxn.oldValuesFetchDescriptor(olderThan: .now.addingTimeInterval(-configuration.expireInterval)))
            expired.forEach(context.delete)
            try context.save()

            Task { [weak self, interval = configuration.pushInterval] in
                while true {
                    try? await Task.sleep(for: .seconds(interval))
                    guard let self else { return }
                    await self.submitQueue()
                }
            }
        }

        func record(_ value: AnalyticsValue) async {
            guard case .loggedIn(let auth) = await LabsPlatform.shared?.authState,
                  let idToken = auth.idToken,
                  let pennkey = JWTUtilities.decodeJWT(idToken)?["pennkey"] as? String else {
                return
            }

            let context = modelExecutor.modelContext
            let latest = (try? context.fetch(AnalyticsTxn.allValuesFetchDescriptor()))?
                .filter { $0.data.contains { $0.key == value.key } }
                .max { $0.timestamp < $1.timestamp }
            if let latest, Date.now.timeIntervalSince1970 - Double(latest.timestamp) < configuration.bufferInterval {
                return
            }

            context.insert(AnalyticsTxn(pennkey: pennkey, timestamp: .now, data: [value]))
            try? context.save()
        }

        func recordAndSubmit(_ value: AnalyticsValue) async {
            await record(value)
            await submitQueue()
        }

        func addTimedOperation(_ operation: AnalyticsTimedOperation, removeDuplicates: Bool) {
            if removeDuplicates {
                activeOperations.removeAll { $0.fullKey == operation.fullKey }
            }
            activeOperations.append(operation)
        }

        /// Records the operation's duration only if it was still active.
        func completeTimedOperation(_ operation: AnalyticsTimedOperation) async {
            let count = activeOperations.count
            activeOperations.removeAll { $0 == operation }
            guard activeOperations.count < count else { return }
            await record(operation.finish())
        }

        func getTimedOperation(_ fullKey: String) -> AnalyticsTimedOperation? {
            activeOperations.first { $0.fullKey == fullKey }
        }

        func focusChanged(_ phase: ScenePhase) {
            activeOperations.removeAll { $0.cancelOnScenePhase.contains(phase) }
        }
    }
}

extension LabsPlatform {
    func notifyAnalyticsPushFailed(_ errors: [PlatformAnalyticsError]) {
        delegate?.labsPlatformAnalytics(pushFailedWithErrors: errors, platform: self)
    }
}

// MARK: Network
extension LabsPlatform.Analytics {
    /// Posts every queued transaction. Concurrent calls while a push is in flight return immediately.
    func submitQueue() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let context = modelExecutor.modelContext
        guard let queued = try? context.fetch(AnalyticsTxn.allValuesFetchDescriptor()), !queued.isEmpty else { return }
        let statics = queued.map(StaticAnalyticsTxnDTO.init(from:))

        var submitted: Set<PersistentIdentifier> = []
        var errors: [PlatformAnalyticsError] = []
        await withTaskGroup(of: Result<PersistentIdentifier, PlatformAnalyticsError>.self) { group in
            for txn in statics {
                group.addTask {
                    do throws(PlatformAnalyticsError) {
                        try await self.post(txn)
                        return .success(txn.id)
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for await outcome in group {
                switch outcome {
                case .success(let id): submitted.insert(id)
                case .failure(let error): errors.append(error)
                }
            }
        }

        for txn in queued where submitted.contains(txn.persistentModelID) {
            context.delete(txn)
        }
        try? context.save()

        if !errors.isEmpty, let platform = await LabsPlatform.shared {
            await platform.notifyAnalyticsPushFailed(errors)
        }
    }

    private func post(_ txn: StaticAnalyticsTxnDTO) async throws(PlatformAnalyticsError) {
        guard let platform = await LabsPlatform.shared else {
            throw .platformError(.platformNotEnabled)
        }

        var request: URLRequest
        do {
            request = try await platform.authorizedURLRequest(url: configuration.endpoint, mode: .accessToken, notifyDelegate: false)
        } catch let error as PlatformError {
            throw .platformError(error)
        } catch {
            throw .other(error)
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let body = try? encoder.encode(txn) else {
            throw .encodingFailed
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw .other(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw .invalidResponse
        }
        guard http.statusCode == 200 else {
            throw .badStatusCode(http.statusCode)
        }
    }
}
