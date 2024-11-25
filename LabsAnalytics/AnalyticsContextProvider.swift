//
//  AnalyticsContextProvider.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import SwiftUI

public struct AnalyticsContextProvider<Content: View>: View {
    @Environment(\.labsAnalytics) var analytics: LabsAnalytics?
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




extension View {
    func logViewAnalytics(subkey: String) -> some View {
        @Environment(\.labsAnalyticsPath) var path: String
        @Environment(\.labsAnalytics) var analytics: LabsAnalytics?
        return (
            self
                .onAppear {
                    guard let analytics else { return }
                    analytics.scheduleAnalyticsPost(AnalyticsValue(key: "\(path).\(subkey).open", value: 1, timestamp: Date.now))
                }
                .onDisappear {
                    guard let analytics else { return }
                    analytics.scheduleAnalyticsPost(AnalyticsValue(key: "\(path).\(subkey).close", value: 1, timestamp: Date.now))
                }
        )
    }
}
