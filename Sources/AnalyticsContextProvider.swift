//
//  AnalyticsContextProvider.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import SwiftUI

public struct AnalyticsContextProvider<Content: View>: View {
    @EnvironmentObject var analytics: LabsAnalytics
    @Environment(\.labsAnalyticsPath) var path: String

    public var content: (AnalyticsContext) -> Content
    public let subkey: String

    public init(subkey: String, @ViewBuilder content: @escaping (AnalyticsContext) -> Content) {
        self.content = content
        self.subkey = subkey
    }

    public var body: some View {
        content(AnalyticsContext(analytics: analytics, key: "\(path).\(subkey)"))
    }
}




public extension View {
    func logViewAnalytics(subkey: String) -> some View {
        @Environment(\.labsAnalyticsPath) var path: String
        @EnvironmentObject var analytics: LabsAnalytics
        return (
            self
                .onAppear {
                    analytics.send(AnalyticsValue(key: "\(path).\(subkey).open", value: 1, timestamp: Date.now))
                }
                .onDisappear {
                    analytics.send(AnalyticsValue(key: "\(path).\(subkey).close", value: 1, timestamp: Date.now))
                }
        )
    }
}
