//
//  JWTUtilities.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 2/4/25.
//

import Foundation

final class JWTUtilities {
    static func decodeJWTData(_ value: String) -> Data? {
        return Data(base64Encoded: value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/") + "===")
    }

    static func decodeJWT(_ jwt: String) -> [String: Any]? {
        let segments = jwt.components(separatedBy: ".")
        
        
        
        //guard segments.count > 1, let payload = decodeJWTPart(segments[1]) else {
            return nil
        //}
        //return payload
    }
    
    
    
}
