//
//  ContentView.swift
//  Avant Motion Companion Watch App
//
//  Created by Peyton Ward on 4/17/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var watchModel = WatchSessionModel.shared
    
    var body: some View {
        VStack(spacing: 8) {
            // Existing header
            HStack {
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Hello, world!")
            }

            // Health / Steps section pulled from phone
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                    Text("Health")
                        .font(.headline)
                }
                HStack {
                    Image(systemName: "figure.walk")
                    Text("Prosthetic Steps")
                    Spacer()
                    Text("\(watchModel.prostheticStepCount)")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }
                if let last = watchModel.lastWriteDate {
                    HStack {
                        Text("Last Sync")
                        Spacer()
                        Text(last, style: .time)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
