import SwiftUI

struct RootTabView: View {
	@SceneStorage("selectedTab") private var selectedTab = "records"

	var body: some View {
		TabView(selection: $selectedTab) {
			NavigationStack {
				RecordsListView()
			}
			.tag("records")
			.tabItem {
				Label("记录", systemImage: "list.bullet")
			}

			NavigationStack {
				TrendsView()
			}
			.tag("trends")
			.tabItem {
				Label("趋势", systemImage: "chart.xyaxis.line")
			}

			NavigationStack {
				SettingsView()
			}
			.tag("settings")
			.tabItem {
				Label("设置", systemImage: "gearshape")
			}
		}
		.onChange(of: selectedTab) { _, newValue in
			Analytics.track("tab_selected", properties: ["tab": newValue])
		}
	}
}
