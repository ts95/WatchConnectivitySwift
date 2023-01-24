//
//  WatchConnectivityService.swift
//  
//
//  Created by Toni Sucic on 24/01/2023.
//

import Combine
import WatchConnectivity

@MainActor open class WatchConnectivityService: NSObject, ObservableObject {
    private let connectivitySession: WCSession
    private var receivedMessageStreamContinuation: AsyncStream<ReceivedMessage>.Continuation?
    private var receivedMessageDataStreamContinuation: AsyncStream<ReceivedMessageData>.Continuation?
    private var receivedUserInfoStreamContinuation: AsyncStream<[String: Any]>.Continuation?
    private var receivedApplicationContextStreamContinuation: AsyncStream<[String: Any]>.Continuation?
#if os(iOS)
    private var isPairedObservation: NSKeyValueObservation?
#endif
    private var isReachableObservation: NSKeyValueObservation?
    private var cancellables = [AnyCancellable]()

    public private(set) var receivedMessageStream: AsyncStream<ReceivedMessage>
    public private(set) var receivedMessageDataStream: AsyncStream<ReceivedMessageData>
    public private(set) var receivedUserInfoStream: AsyncStream<[String: Any]>
    public private(set) var receivedApplicationContextStream: AsyncStream<[String: Any]>

    public var sentApplicationContext: [String: Any] {
        connectivitySession.applicationContext
    }

    public var receivedApplicationContext: [String: Any] {
        connectivitySession.receivedApplicationContext
    }

    @Published public var activationStateResult: Result<WCSessionActivationState, Error>
#if os(iOS)
    @Published public var isPaired: Bool
#endif
    @Published public var isReachable: Bool

    public init(connectivitySession: WCSession = .default) {
        self.connectivitySession = connectivitySession
        self.activationStateResult = .success(connectivitySession.activationState)
#if os(iOS)
        self.isPaired = connectivitySession.isPaired
#endif
        self.isReachable = connectivitySession.isReachable

        var receivedMessageStreamContinuation: AsyncStream<ReceivedMessage>.Continuation?
        var receivedMessageDataStreamContinuation: AsyncStream<ReceivedMessageData>.Continuation?
        var receivedUserInfoStreamContinuation: AsyncStream<[String: Any]>.Continuation?
        var receivedApplicationContextStreamContinuation: AsyncStream<[String: Any]>.Continuation?

        receivedMessageStream = AsyncStream { continuation in
            receivedMessageStreamContinuation = continuation
        }

        receivedMessageDataStream = AsyncStream { continuation in
            receivedMessageDataStreamContinuation = continuation
        }

        receivedUserInfoStream = AsyncStream { continuation in
            receivedUserInfoStreamContinuation = continuation
        }

        receivedApplicationContextStream = AsyncStream { continuation in
            receivedApplicationContextStreamContinuation = continuation
        }

        self.receivedMessageStreamContinuation = receivedMessageStreamContinuation
        self.receivedMessageDataStreamContinuation = receivedMessageDataStreamContinuation
        self.receivedUserInfoStreamContinuation = receivedUserInfoStreamContinuation
        self.receivedApplicationContextStreamContinuation = receivedApplicationContextStreamContinuation

        super.init()

        // An Apple Watch will always support a session.
        // An iOS device will only support a session if there’s a paired Apple Watch.
        if WCSession.isSupported() {
            connectivitySession.delegate = self
            connectivitySession.activate()
        }

#if os(iOS)
        isPairedObservation = connectivitySession.observe(\.isPaired, options: [.new]) { [weak self] session, change in
            Task { @MainActor [self] in
                if let isPaired = change.newValue {
                    self?.isPaired = isPaired
                }
            }
        }
#endif

        isReachableObservation = connectivitySession.observe(\.isReachable, options: [.new]) { [weak self] session, change in
            Task { @MainActor [self] in
                if let isReachable = change.newValue {
                    self?.isReachable = isReachable
                }
            }
        }
    }

    deinit {
#if os(iOS)
        isPairedObservation?.invalidate()
#endif
        isReachableObservation?.invalidate()
    }

    public func sendMessage(_ message: [String: Any], retries: Int = 5) async throws -> [String: Any] {
        if !isReachable {
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        do {
            return try await withCheckedThrowingContinuation { continuation in
                self.connectivitySession.sendMessage(message, replyHandler: { replyMessage in
                    continuation.resume(returning: replyMessage)
                }, errorHandler: { error in
                    continuation.resume(throwing: error)
                })
            }
        } catch {
            if (error as? WCError)?.code == .notReachable && retries > 0 {
                try await Task.sleep(nanoseconds: 200_000_000)
                return try await sendMessage(message, retries: retries - 1)
            } else {
                throw error
            }
        }
    }

    public func sendMessageData(_ data: Data, retries: Int = 5) async throws -> Data {
        if !isReachable {
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        do {
            return try await withCheckedThrowingContinuation { continuation in
                self.connectivitySession.sendMessageData(data, replyHandler: { replyData in
                    continuation.resume(returning: replyData)
                }, errorHandler: { error in
                    continuation.resume(throwing: error)
                })
            }
        } catch {
            if (error as? WCError)?.code == .notReachable && retries > 0 {
                try await Task.sleep(nanoseconds: 200_000_000)
                return try await sendMessageData(data, retries: retries - 1)
            } else {
                throw error
            }
        }
    }

    public func transferUserInfo(_ userInfo: [String: Any]) -> WCSessionUserInfoTransfer {
        connectivitySession.transferUserInfo(userInfo)
    }

    public func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        try connectivitySession.updateApplicationContext(applicationContext)
    }
}

extension WatchConnectivityService: WCSessionDelegate {

    public func session(_ session: WCSession,
                        activationDidCompleteWith activationState: WCSessionActivationState,
                        error: Error?) {
        if let error {
            self.activationStateResult = .failure(error)
        } else {
            self.activationStateResult = .success(activationState)
        }
    }

    public func session(_ session: WCSession,
                        didReceiveMessage message: [String : Any],
                        replyHandler: @escaping ([String : Any]) -> Void) {
        let receivedMessage = ReceivedMessage(message: message, replyHandler: replyHandler)
        receivedMessageStreamContinuation?.yield(receivedMessage)
    }

    public func session(_ session: WCSession,
                        didReceiveMessageData messageData: Data,
                        replyHandler: @escaping (Data) -> Void) {
        let receivedMessageData = ReceivedMessageData(data: messageData, replyHandler: replyHandler)
        receivedMessageDataStreamContinuation?.yield(receivedMessageData)
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        receivedUserInfoStreamContinuation?.yield(userInfo)
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        receivedApplicationContextStreamContinuation?.yield(applicationContext)
    }

#if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {
    }

    public func sessionDidDeactivate(_ session: WCSession) {
        // If the person has more than one watch, and they switch,
        // reactivate their session on the new device.
        connectivitySession.activate()
    }
#endif
}
