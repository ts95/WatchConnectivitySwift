//
//  Result+Codable.swift
//  
//
//  Created by Toni Sucic on 24/01/2023.
//

import Foundation

public typealias CodableError = Error & Codable & Hashable

// Catch-all type-erased codable error type
public struct AnyCodableError: CodableError {
    public let rawErrorString: String
    public let localizedDescription: String

    public init(_ error: Error) {
        self.rawErrorString = String(describing: error)
        self.localizedDescription = error.localizedDescription
    }
}

extension Result: Codable where Success: Codable, Failure: CodableError {

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ResultType.self, forKey: .type) {
        case .success:
            self = .success(try container.decode(Success.self, forKey: .value))
        case .failure:
            self = .failure(try container.decode(Failure.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .success(let value):
            try container.encode(ResultType.success, forKey: .type)
            try container.encode(value, forKey: .value)
        case .failure(let error):
            try container.encode(ResultType.failure, forKey: .type)
            try container.encode(error, forKey: .value)
        }
    }
}

extension Result {
    public enum CodingKeys: CodingKey {
        case type
        case value
    }

    public enum ResultType: Codable {
        case success
        case failure
    }
}
