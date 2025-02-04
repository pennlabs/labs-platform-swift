//
//  LabsAnalytics.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation


// TODO: Work this into the new LabsPlatform object

extension LabsPlatform {
    actor Analytics: ObservableObject, Sendable {
        public static var endpoint: URL = URL(string: "https://platform.pennlabs.org/analytics/")!
        private var queue: [AnalyticsTxn] = []
        private var timer: Timer?

        init() {
            Task {
                await startTimer()
                print("Analytics timer started.")
            }
        }

        private func startTimer() {
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task {
                    await self?.submitQueue()
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
       
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return false
        }
        
        return true
    }
}
