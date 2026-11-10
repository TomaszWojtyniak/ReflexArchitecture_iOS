import InventoryCore
import SwiftUI

/// The tab bar from ~/TabBar, driven by Core: a tap is sent as selectTab, and Core decides
/// what it does (switch tabs, go back to the first screen, or open the report sheet).
struct RootView: View {
    let tabs: TabNavigator

    var body: some View {
        TabView(selection: Binding(get: { tabs.state.selected }, set: { tabs.send(action: .selectTab($0)) })) {
            Tab(MainTab.home.title, systemImage: MainTab.home.icon, value: MainTab.home) {
                StackView(navigator: tabs.home)
            }
            ForEach([MainTab.search, .favorites, .profile], id: \.self) { tab in
                Tab(tab.title, systemImage: tab.icon, value: tab) { PlaceholderView(tab: tab) }
            }
            if #available(iOS 27.0, *) {
                Tab(value: MainTab.report, role: .prominent) { Color.clear } label: { reportLabel }
            } else {
                Tab(value: MainTab.report, role: .search) { Color.clear } label: { reportLabel }
            }
        }
        .tint(.red)
        .sheet(isPresented: Binding(
            get: { tabs.state.isReportPresented },
            set: { if !$0 { tabs.send(action: .dismissReport) } }  // swiped down
        )) {
            ReportSheet(tabs: tabs)
        }
    }

    private var reportLabel: some View { Label(MainTab.report.title, systemImage: MainTab.report.icon) }
}

extension MainTab {
    /// SF Symbols as in ~/TabBar; icons are a view concern, so they stay out of Core.
    var icon: String {
        switch self {
        case .home: "house"
        case .search: "magnifyingglass"
        case .favorites: "heart"
        case .profile: "person.crop.circle"
        case .report: "exclamationmark.bubble.fill"
        }
    }
}

private struct PlaceholderView: View {
    let tab: MainTab

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: tab.icon).font(.system(size: 48)).foregroundStyle(.secondary)
            Text(tab.title).font(.title2.bold())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ReportSheet: View {
    let tabs: TabNavigator

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: MainTab.report.icon).font(.system(size: 40)).foregroundStyle(.red)
                Text(MainTab.report.title).font(.title.bold())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { tabs.send(action: .dismissReport) }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
