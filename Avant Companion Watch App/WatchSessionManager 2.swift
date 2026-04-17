import SwiftUI
import Combine

class ServoViewModel: ObservableObject {
    @Published var servoDegree: Int = 0
    @Published var otherProperty: String = ""

    func apply(context: [String: Any]) {
        if let servoValue = context["servo"] as? Int {
            self.servoDegree = servoValue
        }
        // Existing context handling logic here
    }
}
