//
//  WatchConnectivityRPCRepository.swift
//  
//
//  Created by Toni Sucic on 24/01/2023.
//

import Foundation

@MainActor open class WatchConnectivityRPCRepository<RPCRequest: WatchConnectivityRPCRequest,
                                                     RPCResponse: WatchConnectivityRPCResponse,
                                                     RPCApplicationContext: WatchConnectivityRPCApplicationContext>: ObservableObject {
    private let watchConnectivityService: WatchConnectivityService
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    @Published public var sharedState = RPCApplicationContext()

    public init(watchConnectivityService: WatchConnectivityService) {
        self.watchConnectivityService = watchConnectivityService

        processIncomingMessageData()
        processIncomingApplicationContext()
    }

    public func perform(request: RPCRequest) async throws {
        let data = try jsonEncoder.encode(request)
        let responseData = try await watchConnectivityService.sendMessageData(data)
        let result = try jsonDecoder.decode(Result<RPCResponse, AnyCodableError>.self, from: responseData)
        _ = try result.get()
    }

    public func perform<R: Codable>(request: RPCRequest) async throws -> R {
        let data = try jsonEncoder.encode(request)
        let responseData = try await watchConnectivityService.sendMessageData(data)
        let result = try jsonDecoder.decode(Result<RPCResponse, AnyCodableError>.self, from: responseData)
        let response = try result.get()
        if let returnValue = response.value as? R {
            return returnValue
        } else {
            throw WatchConnectivityRPCRepositoryError.invalidReturnType("\(response) cannot be converted to \(R.self)")
        }
    }

    public func transferSharedState() throws {
        let sharedStateData = try jsonEncoder.encode(sharedState)
        let applicationContext = [
            RPCApplicationContext.key: sharedStateData
        ]
        try watchConnectivityService.updateApplicationContext(applicationContext)
    }

    open func onRequest(_ request: RPCRequest) async throws -> RPCResponse {
        fatalError("onRequest(_:) is unimplemented. Should be overridden in a subclass.")
    }

    open func onProcessingError(_ error: Error) {
        assertionFailure("An error occurred when processing a message: \(error)")
    }

    private func processIncomingMessageData() {
        Task {
            for await receivedMessageData in watchConnectivityService.receivedMessageDataStream {
                do {
                    let request = try jsonDecoder.decode(RPCRequest.self, from: receivedMessageData.data)
                    let requestTask = Task {
                        try await onRequest(request)
                    }
                    let result = await requestTask.result.mapError(AnyCodableError.init)
                    let responseData = try jsonEncoder.encode(result)
                    receivedMessageData.replyHandler(responseData)
                } catch {
                    onProcessingError(error)
                    do {
                        let result = Result<RPCResponse, AnyCodableError>.failure(AnyCodableError(error))
                        let responseData = try jsonEncoder.encode(result)
                        receivedMessageData.replyHandler(responseData)
                    } catch {
                        onProcessingError(error)
                    }
                }
            }
        }
    }

    private func processIncomingApplicationContext() {
        Task {
            for await receivedApplicationContext in watchConnectivityService.receivedApplicationContextStream {
                do {
                    sharedState = try decodeApplicationContext(receivedApplicationContext)
                } catch {
                    onProcessingError(WatchConnectivityRPCRepositoryError.failedToDecodeApplicationContext(AnyCodableError(error)))
                }
            }
        }
    }

    private func decodeApplicationContext(_ applicationContext: [String: Any]) throws -> RPCApplicationContext {
        guard let data = applicationContext[RPCApplicationContext.key] as? Data else {
            throw WatchConnectivityRPCRepositoryError.applicationContextKeyNil
        }
        return try self.jsonDecoder.decode(RPCApplicationContext.self, from: data)
    }
}
