//
//  LabsAnalytics.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation
import Combine

public extension LabsPlatform {
    final actor Analytics: ObservableObject, Sendable {
        public static var endpoint: URL = URL(string: "https://analytics.pennlabs.org/analytics/")!
        
        public static var pushInterval: TimeInterval = 30
        private var queue: [AnalyticsTxn] = [] {
            didSet {
                // This needs to support App Groups in the future, so want to ensure
                // that no data is lost or duplicated.
                let current = UserDefaults.standard.object(forKey: "LabsAnalyticsQueue") as? [AnalyticsTxn] ?? []
                queue = Array(Set(current + queue))
                UserDefaults.standard.set(try? JSONEncoder().encode(queue), forKey: "LabsAnalyticsQueue")
            }
        }
        private var dispatch: (any Cancellable)?

        init() {
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
                  let jwt = JWTUtilities.decodeJWT(auth.idToken),
                  let pennkey: String = jwt["pennkey"] as? String else {
                return
            }
            self.queue.append(AnalyticsTxn(pennkey: pennkey, timestamp: Date.now, data: [value]))
        }
        
        func recordAndSubmit(_ value: AnalyticsValue) async throws {
            await record(value)
            await submitQueue()
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
        guard let platform = await LabsPlatform.shared, var request = try? await platform.authorizedURLRequest(url: LabsPlatform.Analytics.endpoint, mode: .jwt) else {
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
