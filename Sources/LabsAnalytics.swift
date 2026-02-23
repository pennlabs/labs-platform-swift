//
//  LabsAnalytics.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation
import Combine
import SwiftUI
import SwiftData

public extension LabsPlatform {
    final actor Analytics: ObservableObject, Sendable, ModelActor {
        public let modelContainer: ModelContainer
        public let modelExecutor: any ModelExecutor
        
        static let defaultEndpoint: URL = URL(string: "https://analytics.pennlabs.org/analytics/")!
        static let defaultPushInterval: TimeInterval = 30
        static let defaultExpireInterval: TimeInterval = TimeInterval(60 * 60 * 24 * 7) // 7 days expiry
        
        private var activeOperations: [AnalyticsTimedOperation] = []
        private var dispatch: (any Cancellable)?
        
        let endpoint: URL
        let pushInterval: TimeInterval
        let expireInterval: TimeInterval

        init(endpoint: URL = defaultEndpoint, pushInterval: TimeInterval = defaultPushInterval, expireInterval: TimeInterval = defaultExpireInterval) throws {
            self.modelContainer = try ModelContainer(for: AnalyticsTxn.self)
            let context = ModelContext(modelContainer)
            self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
            
            let oldValues: [AnalyticsTxn] = try self.modelExecutor.modelContext.fetch(AnalyticsTxn.oldValuesFetchDescriptor(olderThan: Date.now.addingTimeInterval(-1 * expireInterval)))
            for val in oldValues {
                modelExecutor.modelContext.delete(val)
            }
            self.endpoint = endpoint
            self.pushInterval = pushInterval
            self.expireInterval = expireInterval
            
            Task {
                await startTimer()
            }
        }

        private func startTimer() {
            dispatch = DispatchQueue
                .global(qos: .utility)
                .schedule(after: .init(.now()),
                          interval: .seconds(self.pushInterval),
                          tolerance: .seconds(self.pushInterval / 5)) { [weak self] in
                    guard let self else { return }
                    Task {
                        await self.submitQueue()
                    }
                }
        }
        
        
        func record(_ value: AnalyticsValue) async {
            guard case .loggedIn(let auth) = await LabsPlatform.shared?.authState,
                  let id = auth.idToken,
                  let jwt = JWTUtilities.decodeJWT(id),
                  let pennkey: String = jwt["pennkey"] as? String else {
                return
            }
            self.modelExecutor.modelContext.insert(AnalyticsTxn(pennkey: pennkey, timestamp: Date.now, data: [value]))
        }
        
        func recordAndSubmit(_ value: AnalyticsValue) async throws {
            await record(value)
            await submitQueue()
        }
        
        func addTimedOperation(_ operation: AnalyticsTimedOperation, removeDuplicates: Bool) {
            if removeDuplicates {
                self.activeOperations.removeAll(where: { $0.fullKey == operation.fullKey })
            }
            self.activeOperations.append(operation)
        }
        
        func completeTimedOperation(_ operation: AnalyticsTimedOperation) {
            self.activeOperations.removeAll(where: {$0 == operation})
            Task {
                await record(await operation.finish())
            }
        }
        
        func getTimedOperation(_ fullKey: String) -> AnalyticsTimedOperation? {
            return self.activeOperations.first(where: {$0.fullKey == fullKey})
        }
        
        func focusChanged(_ phase: ScenePhase) {
            let toCancel = self.activeOperations.filter({ op in
                return op.cancelOnScenePhase.contains(where: {$0 == phase})
            })
            
            toCancel.forEach({ op in
                Task {
                    await op.cancel()
                }
            })
            
            self.activeOperations.removeAll(where: { el in
                toCancel.contains(where: {$0 == el})
            })
        }
    }
}

// MARK: Network
extension LabsPlatform.Analytics {
    
    func submitQueue() async {
        guard let toSubmit = try? self.modelExecutor.modelContext.fetch(AnalyticsTxn.allValuesFetchDescriptor()),
              !toSubmit.isEmpty else { return }

        let statics = toSubmit.map({ StaticAnalyticsTxnDTO(from: $0) })
        let succeeded = await withTaskGroup(of: StaticAnalyticsTxnDTO?.self) { group in
            for txn in statics {
                group.addTask {
                    let success = await self.analyticsPostRequest(txn)
                    return success ? txn : nil
                }
            }
            
            var success: [StaticAnalyticsTxnDTO] = []
            for await res in group {
                if let res {
                    success.append(res)
                }
            }
            return success
        }
        
        let intersection = toSubmit.filter { live in
            succeeded.contains(where: { $0.id == live.id })
        }
        for el in intersection {
            self.modelExecutor.modelContext.delete(el)
        }
    }
    
    // true = successful submission (failed submissions should go back in the queue)
    //
    // another design decision: we're only collecting data from logged-in users here,
    // though the analytics engine supports anonymous submissions
    // (from logged in users from some reason)
    private func analyticsPostRequest(_ txn: StaticAnalyticsTxnDTO) async -> Bool {
        guard var request = try? await URLRequest(url: self.endpoint, mode: .jwt) else {
            return false
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let json = JSONEncoder()
        json.keyEncodingStrategy = .convertToSnakeCase
 
        guard let data = try? json.encode(txn) else {
            return false
        }
        
        request.httpBody = data
       
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return false
        }
        
        return true
    }
}
