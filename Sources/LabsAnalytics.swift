//
//  LabsAnalytics.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation
import Combine
import SwiftUI

public extension LabsPlatform {
    final actor Analytics: ObservableObject, Sendable {
        public static var endpoint: URL = URL(string: "https://analytics.pennlabs.org/analytics/")!
        
        public static var pushInterval: TimeInterval = 30
        public static var expireInterval: TimeInterval = TimeInterval(60 * 60 * 24 * 7) // 7 days expiry
        private var queue: Set<AnalyticsTxn> = [] {
            didSet {
                let q = queue
                DispatchQueue.main.async {
                    UserDefaults.standard.setValue(try? JSONEncoder().encode(q), forKey: "LabsAnalyticsQueue")
                }
            }
        }
        private var activeOperations: [AnalyticsTimedOperation] = []
        private var dispatch: (any Cancellable)?

        init() {
            // queue will be assigned the value in userdefaults on the first submission, so we will expire old values
            let data = UserDefaults.standard.data(forKey: "LabsAnalyticsQueue")
            let oldQueue = (try? JSONDecoder().decode(Set<AnalyticsTxn>.self, from: data ?? Data())) ?? []
            self.queue = oldQueue.filter {
                return Date.now.timeIntervalSince(Date.init(timeIntervalSince1970: TimeInterval($0.timestamp))) < LabsPlatform.Analytics.expireInterval
            }
            
            
            Task {
                await startTimer()
                print("Analytics timer started.")
            }
        }

        private func startTimer() {
            dispatch = DispatchQueue
                .global(qos: .utility)
                .schedule(after: .init(.now()),
                          interval: .seconds(LabsPlatform.Analytics.pushInterval),
                          tolerance: .seconds(LabsPlatform.Analytics.pushInterval / 5)) { [weak self] in
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
            self.queue.insert(AnalyticsTxn(pennkey: pennkey, timestamp: Date.now, data: [value]))
        }
        
        func recordAndSubmit(_ value: AnalyticsValue) async throws {
            await record(value)
            await submitQueue()
        }
        
        func addTimedOperation(_ operation: AnalyticsTimedOperation) {
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
        guard !queue.isEmpty else { return }

        let toSubmit = queue
        queue.removeAll()

        await withTaskGroup(of: Void.self) { group in
            for txn in toSubmit {
                group.addTask {
                    if !(await self.analyticsPostRequest(txn)) {
                        await self.record(txn.data.first!)
                    }
                }
            }
        }
    }
    
    // true = successful submission (failed submissions should go back in the queue)
    //
    // another design decision: we're only collecting data from logged-in users here,
    // though the analytics engine supports anonymous submissions
    // (from logged in users from some reason)
    private func analyticsPostRequest(_ txn: AnalyticsTxn) async -> Bool {
        guard var request = try? await URLRequest(url: LabsPlatform.Analytics.endpoint, mode: .jwt) else {
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
