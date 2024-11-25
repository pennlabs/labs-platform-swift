//
//  AnalyticsValue.swift
//  
//
//  Created by Jonathan Melitski on 11/25/24.
//

struct AnalyticsValue: Codable, Equatable {
    let key: String
    let value: Int
    let timestamp: Int

    init(key: String, value: Int, timestamp: Date) {
        self.key = key.replacingOccurrences(of: " ", with: "_")
        self.value = value
        self.timestamp = Int(timestamp.timeIntervalSince1970)
    }
}
