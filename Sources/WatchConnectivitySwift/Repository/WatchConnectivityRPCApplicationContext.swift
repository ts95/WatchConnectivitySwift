//
//  WatchConnectivityRPCApplicationContext.swift
//  
//
//  Created by Toni Sucic on 24/01/2023.
//

import Foundation

public protocol WatchConnectivityRPCApplicationContext: Hashable, Codable {
    init()
}

public extension WatchConnectivityRPCApplicationContext {
    static var key: String {
        String(describing: Self.self)
    }
}
