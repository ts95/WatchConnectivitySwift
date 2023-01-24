//
//  ReceivedMessageData.swift
//  
//
//  Created by Toni Sucic on 24/01/2023.
//

import Foundation

public struct ReceivedMessageData {
    let data: Data
    let replyHandler: (Data) -> Void
}
