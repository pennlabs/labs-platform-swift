//
//  Keychain.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 2/2/25.
//

import Foundation

@MainActor
final class LabsKeychain {
    
    static let labsAccount = "labs-platform"
    
    static func save(_ data: Data, service: String) {
        #if targetEnvironment(simulator)
            return
        #else
        let query = [
            kSecValueData: data,
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: LabsKeychain.labsAccount,
        ] as CFDictionary
        
        // Add data in query to keychain
        let status = SecItemAdd(query, nil)
        
        if status != errSecSuccess {
            // Print out the error
            print("Error: \(status)")
        }
        
        if status == errSecDuplicateItem {
                // Item already exists, thus update it.
                let query = [
                    kSecAttrService: service,
                    kSecAttrAccount: labsAccount,
                    kSecClass: kSecClassGenericPassword,
                ] as CFDictionary

                let attributesToUpdate = [kSecValueData: data] as CFDictionary

                SecItemUpdate(query, attributesToUpdate)
        }
        #endif
    }
    
    static func read(service: String) -> Data? {
        #if targetEnvironment(simulator)
            return nil
        #else
        let query = [
            kSecAttrService: service,
            kSecAttrAccount: LabsKeychain.labsAccount,
            kSecClass: kSecClassGenericPassword,
            kSecReturnData: true
        ] as CFDictionary
        
        var result: AnyObject?
        SecItemCopyMatching(query, &result)
        
        return (result as? Data)
        #endif
    }
    
    static func delete(service: String) {
        #if targetEnvironment(simulator)
            return
        #else
        let query = [
            kSecAttrService: service,
            kSecAttrAccount: LabsKeychain.labsAccount,
            kSecClass: kSecClassGenericPassword,
            ] as CFDictionary
        
        // Delete item from keychain
        SecItemDelete(query)
        #endif
    }
}

// MARK: Platform Credential Storage
extension LabsKeychain {
    static func savePlatformCredential(_ credential: PlatformAuthCredentials) {
        guard let data = try? JSONEncoder().encode(credential) else {
            return
        }
        
        LabsKeychain.save(data, service: "auth-credentials")
    }
    
    static func loadPlatformCredential() -> PlatformAuthCredentials? {
        guard let data = LabsKeychain.read(service: "auth-credentials") else {
            return nil
        }
        
        return try? JSONDecoder().decode(PlatformAuthCredentials.self, from: data)
    }
    
    static func clearPlatformCredential() {
        LabsKeychain.delete(service: "auth-credentials")
    }
    
    static func hasPlatformCredential() -> Bool {
        return loadPlatformCredential() != nil
    }
}
