import SwiftUI

struct FirmwareUpdateView: View {
    @EnvironmentObject var appSettings: AppSettings
    @State private var isChecking = false
    @State private var release: GitHubRelease?
    @State private var errorMessage: String?
    
    let currentVersion: String?
    private let service = FirmwareUpdateService()
    
    var body: some View {
        NavigationStack {
            Group {
                if isChecking {
                    ProgressView("Checking for updates...")
                } else if let release {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading) {
                                    Text("Latest: \(release.tag_name)")
                                        .font(.title3.bold())
                                    if let name = release.name, !name.isEmpty {
                                        Text(name).foregroundStyle(.secondary)
                                    }
                                    if let current = currentVersion {
                                        Text("Current: \(current)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            if let body = release.body, !body.isEmpty {
                                Text("Changelog")
                                    .font(.headline)
                                Text(body)
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .padding()
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                Text("No changelog provided.")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 10)
                            Button("Done") { }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    }
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(errorMessage).multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    Text("Tap Check to look for firmware updates.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Firmware Update")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Check") { Task { await check() } }
                        .disabled(isChecking)
                }
            }
            .task { await check() }
        }
    }
    
    private func check() async {
        isChecking = true
        errorMessage = nil
        do {
            let rel = try await service.fetchLatestRelease(owner: appSettings.firmwareRepoOwner, repo: appSettings.firmwareRepoName)
            await MainActor.run {
                self.release = rel
                self.isChecking = false
            }
        } catch let FirmwareUpdateError.notFound {
            await MainActor.run {
                self.errorMessage = "No releases found for \(appSettings.firmwareRepoOwner)/\(appSettings.firmwareRepoName)."
                self.isChecking = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to check updates: \(error.localizedDescription)"
                self.isChecking = false
            }
        }
    }
}
