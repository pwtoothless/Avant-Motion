import SwiftUI

struct FirmwareUpdateView: View {
    @EnvironmentObject var bt: BluetoothManager
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var isChecking = false
    @State private var release: GitHubRelease?
    @State private var errorMessage: String?
    
    let currentVersion: String?
    private let service = FirmwareUpdateService()

    private var binaryAsset: GitHubReleaseAsset? {
        guard let release else { return nil }
        return service.latestBinaryAsset(in: release)
    }

    private var isUpdateAvailable: Bool {
        guard let release else { return false }
        return service.isUpdateAvailable(currentVersion: currentVersion, latestVersion: release.tag_name)
    }

    private var isUpdating: Bool {
        switch bt.otaStatus {
        case .idle, .complete, .failed:
            return false
        default:
            return true
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isChecking {
                        ProgressView("Checking for updates...")
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if let release {
                        HStack(alignment: .top) {
                            Image(systemName: isUpdateAvailable ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(isUpdateAvailable ? .blue : .green)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Latest: \(release.tag_name)")
                                    .font(.title3.bold())
                                if let name = release.name, !name.isEmpty {
                                    Text(name)
                                        .foregroundStyle(.secondary)
                                }
                                Text("Current: \(currentVersion ?? "Unknown")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(isUpdateAvailable ? "Update available" : "You are up to date")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(isUpdateAvailable ? .blue : .green)
                            }
                            Spacer()
                        }

                        if let asset = binaryAsset {
                            Label(asset.name, systemImage: "doc.zipper")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("This release does not include a .bin firmware asset.")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }

                        otaStatusSection

                        if let body = release.body, !body.isEmpty {
                            Text("Changelog")
                                .font(.headline)
                            Text(body)
                                .font(.body)
                                .textSelection(.enabled)
                                .padding()
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }

                        HStack {
                            Button("Close") { dismiss() }
                                .buttonStyle(.bordered)

                            Spacer()

                            Button(isUpdating ? "Updating..." : "Update") {
                                startUpdate()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!isUpdateAvailable || binaryAsset == nil || bt.connectedPeripheral == nil || isUpdating)
                        }
                    } else if let errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(errorMessage)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else {
                        Text("Checking for firmware updates...")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Firmware Update")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Check") { Task { await check() } }
                        .disabled(isChecking || isUpdating)
                }
            }
            .task { await check() }
        }
    }

    @ViewBuilder
    private var otaStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Update Status")
                .font(.headline)

            Text(bt.otaStatus.rawValue)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if bt.otaStatus == .downloadingFirmware || bt.otaStatus == .uploadingFirmware {
                ProgressView(value: bt.otaProgress)
                    .progressViewStyle(.linear)
                Text(String(format: "%.0f%%", bt.otaProgress * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let otaError = bt.otaError, bt.otaStatus == .failed {
                Text(otaError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if bt.connectedPeripheral == nil {
                Text("Connect to the prosthetic over Bluetooth before starting an update.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func startUpdate() {
        guard let release, let asset = binaryAsset, let downloadURL = asset.downloadURL else {
            errorMessage = "The latest release does not include a downloadable .bin asset."
            return
        }

        errorMessage = nil
        bt.initiateFirmwareUpdate(
            downloadURL: downloadURL,
            fileName: asset.name,
            targetVersion: release.tag_name
        )
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
        } catch FirmwareUpdateError.notFound {
            await MainActor.run {
                self.errorMessage = "No releases found for \(appSettings.firmwareRepoOwner)/\(appSettings.firmwareRepoName)."
                self.release = nil
                self.isChecking = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to check updates: \(error.localizedDescription)"
                self.release = nil
                self.isChecking = false
            }
        }
    }
}
