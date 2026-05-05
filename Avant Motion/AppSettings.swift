import Foundation
import Combine

final class AppSettings: ObservableObject {
    @Published var firmwareRepoOwner: String {
        didSet { save() }
    }
    @Published var firmwareRepoName: String {
        didSet { save() }
    }
    
    private static let ownerKey = "app.firmwareRepoOwner"
    private static let nameKey = "app.firmwareRepoName"
    
    init() {
        self.firmwareRepoOwner = UserDefaults.standard.string(forKey: Self.ownerKey) ?? "your-github-username"
        self.firmwareRepoName = UserDefaults.standard.string(forKey: Self.nameKey) ?? "your-repo"
    }
    
    private func save() {
        UserDefaults.standard.set(firmwareRepoOwner, forKey: Self.ownerKey)
        UserDefaults.standard.set(firmwareRepoName, forKey: Self.nameKey)
    }
}
