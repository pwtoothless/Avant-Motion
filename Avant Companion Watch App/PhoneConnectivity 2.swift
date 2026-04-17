import Combine
import Foundation

class SomeClass {
    private var cancellables = Set<AnyCancellable>()

    func bind(to bluetooth: BluetoothManager) {
        Publishers.CombineLatest4(
            bluetooth.$gyro1Values,
            bluetooth.$gyro2Values,
            bluetooth.$gyro3Values,
            bluetooth.$currentServoDegree
        )
        .combineLatest(bluetooth.$batteryPercentage)
        .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
        .sink { [weak self] tripleAndServo, battery in
            let (g1, g2, g3, servo) = tripleAndServo
            self?.sendState(gyro1: g1, gyro2: g2, gyro3: g3, battery: battery, servo: servo)
        }
        .store(in: &cancellables)
    }

    private func sendState(gyro1: [String], gyro2: [String], gyro3: [String], battery: Int, servo: Int) {
        let context: [String: Any] = [
            "gyro1": gyro1,
            "gyro2": gyro2,
            "gyro3": gyro3,
            "battery": battery,
            "servo": servo
        ]
        // Existing implementation for sending state using context
    }
}

class BluetoothManager: ObservableObject {
    @Published var gyro1Values: [String] = []
    @Published var gyro2Values: [String] = []
    @Published var gyro3Values: [String] = []
    @Published var currentServoDegree: Int = 0
    @Published var batteryPercentage: Int = 100
}
