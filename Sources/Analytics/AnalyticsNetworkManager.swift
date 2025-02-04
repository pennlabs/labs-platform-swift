//
//  AnalyticsNetworkManager.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation


class AnalyticsNetworkManager {
    let token: String
    let pennkey: String
    let url: URL
    var queue: [AnalyticsValue] = []
    
    init(token: String, pennkey: String, url: URL) {
        self.token = token
        self.pennkey = pennkey
        self.url = url
    }
    
    func submit() async throws -> Void {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // TODO: Authenticate request
        
        let send = queue
        let txn = AnalyticsTxn(pennkey: pennkey, data: queue)
        
        guard let txnJson = try? JSONEncoder().encode(txn) else {
            throw AnalyticsError.invalidData
        }
        
        queue.removeAll()
        
        request.httpBody = txnJson
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                queue.append(contentsOf: send)
                throw AnalyticsError.invalidResponse
            }
        } catch {
            queue.append(contentsOf: send)
            throw error
        }
    }
    
    func addValue(_ value: AnalyticsValue) {
        queue.append(value)
    }
}

public enum AnalyticsError: Error {
    case invalidData
    case invalidResponse
}
