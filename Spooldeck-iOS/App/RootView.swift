import SwiftUI

/// Navigation targets shared by every tab's stack.
enum Route: Hashable {
    case spool(id: Int, logUsage: Bool = false)
    case filament(id: Int)
    case spools(filter: SpoolFilter)
    case prusament(url: String)
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.phase {
        case .needsServer:
            ServerView()
        case .needsLogin:
            LoginView()
        case .signedIn:
            MainTabView()
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @State private var selection = 0

    var body: some View {
        @Bindable var app = app
        TabView(selection: $selection) {
            Tab("Dashboard", systemImage: "square.grid.2x2", value: 0) {
                NavigationStack { DashboardView().withRoutes() }
            }
            Tab("Spools", systemImage: "shippingbox", value: 1) {
                NavigationStack { SpoolListView().withRoutes() }
            }
            Tab("Filaments", systemImage: "paintpalette", value: 3) {
                NavigationStack { FilamentListView().withRoutes() }
            }
            Tab("Scan", systemImage: "viewfinder", value: 2) {
                ScanTab()
            }
            Tab("Settings", systemImage: "gearshape", value: 4) {
                NavigationStack { SettingsView().withRoutes() }
            }
        }
        .tint(Theme.primary)
        .sheet(item: Binding(
            get: { app.labelSpoolIds.map(LabelRequest.init) },
            set: { app.labelSpoolIds = $0?.ids }
        )) { request in
            LabelsWebView(spoolIds: request.ids)
        }
    }
}

private struct LabelRequest: Identifiable {
    let ids: [Int]
    var id: String { ids.map(String.init).joined(separator: ",") }
}

extension View {
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .spool(let id, let logUsage):
                SpoolDetailView(spoolId: id, openLogUsage: logUsage)
            case .filament(let id):
                FilamentDetailView(filamentId: id)
            case .spools(let filter):
                SpoolListView(initialFilter: filter)
            case .prusament(let url):
                PrusamentImportView(url: url)
            }
        }
    }
}
