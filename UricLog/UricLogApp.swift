import SwiftUI
import CoreData

@main
struct UricLogApp: App {
	@StateObject private var persistenceController: PersistenceController

	init() {
		let iCloudEnabled = UserDefaults.standard.bool(forKey: AppSettingsKey.iCloudEnabled)
		_persistenceController = StateObject(wrappedValue: PersistenceController(iCloudEnabled: iCloudEnabled))
	}

	var body: some Scene {
		WindowGroup {
			Group {
				if persistenceController.isLoaded {
					RootTabView()
						.environment(\.managedObjectContext, persistenceController.container.viewContext)
						.environmentObject(persistenceController)
				} else {
					ProgressView("正在加载数据...")
						.progressViewStyle(.circular)
				}
			}
			.alert(
				"存储初始化提示",
				isPresented: Binding(
					get: { persistenceController.loadErrorMessage != nil },
					set: { newValue in
						if !newValue { persistenceController.loadErrorMessage = nil }
					}
				)
			) {
				Button("知道了") {}
			} message: {
				Text(persistenceController.loadErrorMessage ?? "")
			}
		}
	}
}
