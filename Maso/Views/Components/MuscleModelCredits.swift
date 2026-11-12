import SwiftUI

struct CreditsScreen: View {
    var body: some View {
        List {
            Section("Exercise photos") {
                Text("Exercise photos via Pexels.")
                Link("Pexels License", destination: URL(string: "https://www.pexels.com/license/")!)
            }
            Section("3D muscle model") {
                Link("Ecorche - Anatomy study", destination: URL(string: "https://skfb.ly/66Wsn")!)
                Text("Beatriz Gomez Santamaria")
                Link("Creative Commons Attribution 4.0", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                Text("Model adapted for Masso: mirrored muscle groups, smoother surfaces, adjusted proportions and fatigue colors.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Credits")
        .navigationBarTitleDisplayMode(.inline)
    }
}
