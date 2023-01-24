//
//  WatchConnectivityRPCResponse.swift
//  
//
//  Created by Toni Sucic on 24/01/2023.
//

import Foundation

public protocol WatchConnectivityRPCResponse: Codable {
    var value: Any { get }
}
