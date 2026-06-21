import Foundation

final class ICloudSettingsSync: ObservableObject {
	private let store = NSUbiquitousKeyValueStore.default
	private let userDefaults: UserDefaults
	private var isApplyingRemoteChange = false
	private var lastICloudEnabled: Bool

	private let syncedKeys: [String] = [
		AppSettingsKey.userGender,
		AppSettingsKey.targetEnabled,
		AppSettingsKey.targetValue,
		AppSettingsKey.preferredUnit,
	]

	init(userDefaults: UserDefaults = .standard) {
		self.userDefaults = userDefaults
		self.lastICloudEnabled = userDefaults.bool(forKey: AppSettingsKey.iCloudEnabled)

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleUserDefaultsChanged),
			name: UserDefaults.didChangeNotification,
			object: userDefaults
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleICloudStoreChanged),
			name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
			object: store
		)

		if lastICloudEnabled {
			reconcileOnEnable()
		}
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	@objc private func handleUserDefaultsChanged() {
		let enabled = userDefaults.bool(forKey: AppSettingsKey.iCloudEnabled)
		if enabled != lastICloudEnabled {
			lastICloudEnabled = enabled
			if enabled {
				reconcileOnEnable()
			}
			return
		}

		guard enabled, !isApplyingRemoteChange else { return }
		pushLocalToICloud(keys: syncedKeys)
	}

	@objc private func handleICloudStoreChanged(_ notification: Notification) {
		guard userDefaults.bool(forKey: AppSettingsKey.iCloudEnabled) else { return }
		let keys = (notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
		let filtered = keys.filter { syncedKeys.contains($0) }
		pullICloudToLocal(keys: filtered.isEmpty ? syncedKeys : filtered)
	}

	private func reconcileOnEnable() {
		store.synchronize()

		var keysToPull: [String] = []
		var keysToPush: [String] = []
		for key in syncedKeys {
			if store.object(forKey: key) != nil {
				keysToPull.append(key)
			} else {
				keysToPush.append(key)
			}
		}

		if !keysToPull.isEmpty {
			pullICloudToLocal(keys: keysToPull)
		}
		if !keysToPush.isEmpty {
			pushLocalToICloud(keys: keysToPush)
		}
	}

	private func pushLocalToICloud(keys: [String]) {
		for key in keys {
			switch key {
			case AppSettingsKey.userGender, AppSettingsKey.preferredUnit:
				if let value = userDefaults.string(forKey: key) {
					store.set(value, forKey: key)
				}
			case AppSettingsKey.targetEnabled:
				store.set(userDefaults.bool(forKey: key), forKey: key)
			case AppSettingsKey.targetValue:
				store.set(userDefaults.double(forKey: key), forKey: key)
			default:
				break
			}
		}
		store.synchronize()
	}

	private func pullICloudToLocal(keys: [String]) {
		isApplyingRemoteChange = true
		defer { isApplyingRemoteChange = false }

		for key in keys {
			guard store.object(forKey: key) != nil else { continue }
			switch key {
			case AppSettingsKey.userGender, AppSettingsKey.preferredUnit:
				if let value = store.string(forKey: key), userDefaults.string(forKey: key) != value {
					userDefaults.set(value, forKey: key)
				}
			case AppSettingsKey.targetEnabled:
				let value = store.bool(forKey: key)
				if userDefaults.bool(forKey: key) != value {
					userDefaults.set(value, forKey: key)
				}
			case AppSettingsKey.targetValue:
				let value = store.double(forKey: key)
				if userDefaults.double(forKey: key) != value {
					userDefaults.set(value, forKey: key)
				}
			default:
				break
			}
		}
	}
}
