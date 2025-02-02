//
//  AnalyticsValue.swift
//  
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation

public struct AnalyticsValue: Codable, Equatable, Identifiable, Hashable, Sendable {
    public let id = UUID()
    let key: String
    let value: Int
    let timestamp: Int

    init(key: String, value: Int, timestamp: Date) {
        self.key = key.replacingOccurrences(of: " ", with: "_")
        self.value = value
        self.timestamp = Int(timestamp.timeIntervalSince1970)
    }
}
