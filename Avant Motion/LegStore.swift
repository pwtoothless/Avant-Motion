import Foundation
import Combine

final class LegStore: ObservableObject {
    @Published var legs: [ProstheticLeg] = [] {
        didSet { save() }
    }
    @Published var selectedLegId: UUID? {
        didSet { UserDefaults.standard.set(selectedLegId?.uuidString, forKey: Self.selectedKey) }
    }
    
    private static let storageKey = "prosthetic.legs"
    private static let selectedKey = "prosthetic.selectedLegId"
    
    init() {
        load()
    }
    
    func add(_ leg: ProstheticLeg) {
        legs.append(leg)
    }
    
    func remove(_ leg: ProstheticLeg) {
        legs.removeAll { $0.id == leg.id }
    }
    
    func leg(with id: UUID?) -> ProstheticLeg? {
        guard let id else { return nil }
        return legs.first { $0.id == id }
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey) {
            if let decoded = try? JSONDecoder().decode([ProstheticLeg].self, from: data) {
                self.legs = decoded
            }
        }
        if let sel = UserDefaults.standard.string(forKey: Self.selectedKey), let uuid = UUID(uuidString: sel) {
            self.selectedLegId = uuid
        }
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(legs) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
