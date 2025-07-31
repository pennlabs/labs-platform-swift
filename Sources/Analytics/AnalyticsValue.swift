//
//  AnalyticsValue.swift
//  
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation

public struct AnalyticsValue: Codable, Equatable, Sendable, Hashable {
    let key: String
    let value: String

    init(key: String, value: String, timestamp: Date) {
        self.key = key.replacingOccurrences(of: " ", with: "_")
        self.value = value
    }
}
