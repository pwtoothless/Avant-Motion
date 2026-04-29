import Foundation
import Combine
import WatchConnectivity

// Receives updates from the iPhone and publishes them for the watch UI
final class WatchSessionModel: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSessionModel()

    @Published var prostheticStepCount: Int = 0
    @Published var lastWriteDate: Date?

    private override init() {
        super.init()
        activate()
    }

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

    func activate() {
        session?.delegate = self
        session?.activate()
    }

    // MARK: - WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        updateFrom(message: message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        updateFrom(message: applicationContext)
    }

    private func updateFrom(message: [String: Any]) {
        DispatchQueue.main.async {
            if let count = message["prostheticStepCount"] as? Int {
                self.prostheticStepCount = count
            }
            if let ts = message["lastWriteDate"] as? TimeInterval {
                self.lastWriteDate = Date(timeIntervalSince1970: ts)
            }
        }
    }
}
