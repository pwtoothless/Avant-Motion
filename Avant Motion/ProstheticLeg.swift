import Foundation

enum LegSide: String, Codable, CaseIterable, Identifiable {
    case left = "Left"
    case right = "Right"
    
    var id: String { rawValue }
}

struct ProstheticLeg: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var side: LegSide
    /// The CoreBluetooth peripheral identifier for this leg, if known.
    var peripheralId: UUID?
    /// Last known firmware version for this leg (if reported by the device).
    var firmwareVersion: String?
    
    init(id: UUID = UUID(), name: String, side: LegSide, peripheralId: UUID? = nil, firmwareVersion: String? = nil) {
        self.id = id
        self.name = name
        self.side = side
        self.peripheralId = peripheralId
        self.firmwareVersion = firmwareVersion
    }
}
