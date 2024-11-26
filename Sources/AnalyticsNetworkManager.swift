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
    
    init(token: String, pennkey: String, url: URL) {
        self.token = token
        self.pennkey = pennkey
        self.url = url
    }
    
    private func submit(_ txn: AnalyticsTxn, completion: @Sendable @escaping (Result<Any?, Error>) -> Void){
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "X-Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        guard let txnJson = try? JSONEncoder().encode(txn) else {
            completion(.failure(AnalyticsError.invalidData))
            return
        }
        
        request.httpBody = txnJson
        
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            
            guard let httpResponse = response as? HTTPURLResponse, let data = data, httpResponse.statusCode == 200 else {
                completion(.failure(AnalyticsError.invalidResponse))
                return
            }
            completion(.success(nil))
        }
        task.resume()
    }
    
    public func submitValue(_ value: AnalyticsValue) {
            submit(AnalyticsTxn(pennkey: pennkey, data: [value])) { _ in
        }
    }
}

public enum AnalyticsError: Error {
    case invalidData
    case invalidResponse
}
