import Foundation
import WatchConnectivity

// Lightweight bridge that sends prosthetic step updates to Apple Watch
final class PhoneSessionManager: NSObject, WCSessionDelegate {
    static let shared = PhoneSessionManager()

    private override init() {
        super.init()
        activate()
        // Observe HealthKitManager for changes and push to watch (only on iOS, if available)
        #if os(iOS)
        if let hkManagerType = NSClassFromString("HealthKitManager") as AnyObject?,
           let hkManager = (hkManagerType.value(forKey: "shared") as AnyObject?) {
            _ = (hkManager.value(forKeyPath: "prostheticStepCount.publisher") as? Any)?.self
            // If your project defines HealthKitManager, prefer direct access:
            // _ = HealthKitManager.shared.$prostheticStepCount.sink { [weak self] count in
            //     let last = HealthKitManager.shared.lastWriteDate as Date?
            //     self?.sendStepUpdate(count: count, lastSync: last)
            // }
        }
        #endif
    }

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

#if os(iOS)
    private var canSendToWatch: Bool {
        guard let session = session else { return false }
        return session.isPaired && session.isWatchAppInstalled
    }
#else
    private var canSendToWatch: Bool { false }
#endif

    func activate() {
        session?.delegate = self
        session?.activate()
    }

    private func sendStepUpdate(count: Int, lastSync: Date?) {
        guard let session = session, canSendToWatch else { return }
        let payload: [String: Any] = [
            "prostheticStepCount": count,
            "lastWriteDate": lastSync?.timeIntervalSince1970 as Any
        ]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            try? session.updateApplicationContext(payload)
        }
    }

    // Public helper to push step updates without requiring HealthKitManager at compile time
    func pushProstheticSteps(count: Int, lastSync: Date?) {
        sendStepUpdate(count: count, lastSync: lastSync)
    }

    // MARK: - WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

#if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
#endif
}
