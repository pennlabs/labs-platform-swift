//
//  JWTUtilities.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 2/4/25.
//

import Foundation

final class JWTUtilities {
    private static func decodeJWTPart(_ value: String) -> [String: Any]? {
        guard let data = Data(base64Encoded: value.replacingOccurrences(of: "-", with: "+")
                                                 .replacingOccurrences(of: "_", with: "/") + "===") else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
    }

    static func decodeJWT(_ jwt: String) -> [String: Any]? {
        let segments = jwt.components(separatedBy: ".")
        guard segments.count > 1, let payload = decodeJWTPart(segments[1]) else {
            return nil
        }
        return payload
    }
}
