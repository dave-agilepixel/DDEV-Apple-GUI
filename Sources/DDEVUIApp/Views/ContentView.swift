import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Label("Projects", systemImage: "shippingbox")
                Label("Running", systemImage: "play.circle")
                Label("WordPress", systemImage: "w.circle")
                Label("Settings", systemImage: "gearshape")
            }
            .navigationTitle("DDEVUI")
        } content: {
            Text("Projects")
                .font(.title)
        } detail: {
            Text("Select a project")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
