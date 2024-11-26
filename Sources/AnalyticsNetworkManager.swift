//
//  AnalyticsNetworkManager.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation

class AnalyticsNetworkManager {
    let token: String
    let url: URL
    
    init(token: String, url: URL) {
        self.token = token
        self.url = url
    }
    
    func submit(_ txn: AnalyticsTxn) async -> Result<Any?, Error> {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "X-Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        guard let txnJson = try? JSONEncoder().encode(txn) else {
            return .failure(.invalidData)
        }
        
        request.httpBody = txnJson
        
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let httpResponse = response as? HTTPURLResponse, let data = data, httpResponse.statusCode == 200 else {
                return .failure(.invalidResponse)
            }
            
            return .success(nil)
        }
    }
    
    
    
}

public enum AnalyticsError: Error {
    case invalidData
    case invalidResponse
}
