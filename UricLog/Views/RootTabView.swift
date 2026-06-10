import SwiftUI

struct RootTabView: View {
	var body: some View {
		TabView {
			NavigationStack {
				RecordsListView()
			}
			.tabItem {
				Label("记录", systemImage: "list.bullet")
			}

			NavigationStack {
				TrendsView()
			}
			.tabItem {
				Label("趋势", systemImage: "chart.xyaxis.line")
			}

			NavigationStack {
				SettingsView()
			}
			.tabItem {
				Label("设置", systemImage: "gearshape")
			}
		}
	}
}

