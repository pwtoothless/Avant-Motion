import SwiftUI

struct LegSettingsView: View {
    @EnvironmentObject var legs: LegStore
    
    @State private var newName: String = ""
    @State private var newSide: LegSide = .right
    
    var body: some View {
        Section("Prosthetic Legs") {
            if legs.legs.isEmpty {
                Text("No legs added yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(legs.legs) { leg in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(leg.name).font(.headline)
                            Text(leg.side.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if legs.selectedLegId == leg.id {
                            StatusBadge(text: "Selected", color: .blue)
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) { legs.remove(leg) } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
            HStack {
                TextField("New leg name", text: $newName)
                Picker("Side", selection: $newSide) {
                    ForEach(LegSide.allCases) { side in
                        Text(side.rawValue).tag(side)
                    }
                }
                .pickerStyle(.menu)
                Button("Add") {
                    guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    let leg = ProstheticLeg(name: newName, side: newSide)
                    legs.add(leg)
                    newName = ""
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
