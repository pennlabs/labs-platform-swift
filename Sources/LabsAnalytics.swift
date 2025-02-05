//
//  LabsAnalytics.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation


// TODO: Work this into the new LabsPlatform object

public extension LabsPlatform {
    actor Analytics: ObservableObject {
        public static var endpoint: URL = URL(string: "https://platform.pennlabs.org/analytics/")!
        private var queue: [AnalyticsValue] = []
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
        
        
        func record(_ value: AnalyticsValue) {
            self.queue.append(value)
        }
        
        func recordAndSubmit(_ value: AnalyticsValue) async throws {
            record(value)
            Task {
                await submitQueue()
            }
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
            for value in toSubmit {
                group.addTask {
                    if !(await self.analyticsPostRequest(value)) {
                        await self.record(value)
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
    private func analyticsPostRequest(_ value: AnalyticsValue) async -> Bool {
        guard let platform = await LabsPlatform.shared, var request = try? await platform.authorizedURLRequest(url: LabsPlatform.Analytics.endpoint, mode: .jwt) else {
            return false
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        
        var json = JSONEncoder()
        json.keyEncodingStrategy = .convertToSnakeCase
        
        guard case .loggedIn(let auth) = await platform.authState,
              let jwt = JWTUtilities.decodeJWT(auth.idToken),
              let pennkey: String = jwt["pennkey"] as? String else {
            return false
        }
        
        let txn = AnalyticsTxn(pennkey: pennkey, data: [value])
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
