//
//  ReceivedMessage.swift
//  
//
//  Created by Toni Sucic on 24/01/2023.
//

import Foundation

public struct ReceivedMessage {
    let message: [String: Any]
    let replyHandler: ([String: Any]) -> Void
}
