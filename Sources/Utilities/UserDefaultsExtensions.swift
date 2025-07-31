//
//  UserDefaultsExtensions.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 4/14/25.
//

import Foundation

extension UserDefaults {
    static let cookieStorageKey: String = "labs-platform-cookie-storage"
    
    func savePlatformHTTPCookies(_ cookies: [HTTPCookie]) {
        var cookieDict = [String: AnyObject]()
        for cookie in cookies {
            cookieDict[cookie.name + cookie.domain] = cookie.properties as AnyObject?
        }

        self.set(cookieDict, forKey: UserDefaults.cookieStorageKey)
    }
    
    func clearPlatformHTTPCookies() {
        self.removeObject(forKey: UserDefaults.cookieStorageKey)
    }
    
    func loadPlatformHTTPCookies() {
        if let cookieDictionary = self.dictionary(forKey: UserDefaults.cookieStorageKey) {
            for (_, cookieProperties) in cookieDictionary {
                if let cookie = HTTPCookie(properties: cookieProperties as! [HTTPCookiePropertyKey: Any] ) {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
            }
        }
    }
}
