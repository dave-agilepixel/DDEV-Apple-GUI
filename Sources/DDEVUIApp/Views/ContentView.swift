import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ProjectDashboardViewModel()

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
            ProjectListView(viewModel: viewModel)
        } detail: {
            ProjectInspectorView(viewModel: viewModel)
        }
        .task {
            await viewModel.refresh()
        }
        .toolbar {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }
}

#Preview {
    ContentView()
}
