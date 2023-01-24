//
//  WatchConnectivityRPCRepositoryError.swift
//  
//
//  Created by Toni Sucic on 24/01/2023.
//

import Foundation

public enum WatchConnectivityRPCRepositoryError: CodableError {
    case invalidReturnType(String)
    case applicationContextKeyNil
    case failedToDecodeApplicationContext(AnyCodableError)
}
