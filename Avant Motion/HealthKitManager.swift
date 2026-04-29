import Foundation
import HealthKit
import Combine

final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()
    private let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!

    @Published private(set) var isHealthDataAvailable: Bool = HKHealthStore.isHealthDataAvailable()
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastWriteDate: Date?
    @Published private(set) var lastWrittenDelta: Int = 0

    // Latest cumulative count coming from the prosthetic over BLE
    @Published private(set) var prostheticStepCount: Int = 0

    // The last cumulative count we successfully wrote to HealthKit
    private var lastSyncedCount: Int = 0

    private var writeTimer: Timer?

    private init() {
        // Initialize authorization state
        refreshAuthorizationStatus()
        // Set up a periodic writer (every 2 minutes)
        DispatchQueue.main.async {
            self.writeTimer?.invalidate()
            self.writeTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
                self?.writePendingStepsIfNeeded()
            }
        }
    }

    deinit {
        writeTimer?.invalidate()
    }

    func requestAuthorization() {
        guard isHealthDataAvailable else {
            DispatchQueue.main.async { self.lastError = "Health data not available on this device." }
            return
        }
        let toShare: Set<HKSampleType> = [stepType]
        let toRead: Set<HKObjectType> = [stepType]
        healthStore.requestAuthorization(toShare: toShare, read: toRead) { [weak self] success, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.lastError = error.localizedDescription
                }
                self?.refreshAuthorizationStatus()
            }
        }
    }

    func refreshAuthorizationStatus() {
        guard isHealthDataAvailable else {
            isAuthorized = false
            return
        }
        let status = healthStore.authorizationStatus(for: stepType)
        isAuthorized = (status == .sharingAuthorized)
    }

    // Receive an updated cumulative step count from the prosthetic
    func receiveProstheticStepCount(_ count: Int) {
        DispatchQueue.main.async {
            self.prostheticStepCount = max(0, count)
        }
    }

    // Manually trigger a write (optional, primarily for testing)
    func flushPendingSteps() {
        writePendingStepsIfNeeded()
    }

    private func writePendingStepsIfNeeded() {
        DispatchQueue.main.async {
            let currentCount = self.prostheticStepCount
            let authorized = self.isAuthorized
            guard authorized else { return }

            let delta = currentCount - self.lastSyncedCount
            guard delta > 0 else { return }

            let endDate = Date()
            let startDate = self.lastWriteDate ?? endDate.addingTimeInterval(-120)

            let quantity = HKQuantity(unit: HKUnit.count(), doubleValue: Double(delta))
            let sample = HKQuantitySample(type: self.stepType, quantity: quantity, start: startDate, end: endDate)

            self.healthStore.save(sample) { [weak self] success, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.lastError = error.localizedDescription
                        return
                    }
                    if success {
                        self?.lastSyncedCount = currentCount
                        self?.lastWriteDate = endDate
                        self?.lastWrittenDelta = delta
                        self?.lastError = nil
                    }
                }
            }
        }
    }
}

// NOTE:
// - Enable the HealthKit capability for your target.
// - Add NSHealthShareUsageDescription and NSHealthUpdateUsageDescription to your Info.plist with appropriate user-facing descriptions.

