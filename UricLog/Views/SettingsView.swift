import SwiftUI
import CoreData

struct SettingsView: View {
	@Environment(\.managedObjectContext) private var viewContext
	@EnvironmentObject private var persistence: PersistenceController
	@FocusState private var focusedField: FocusField?
	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(keyPath: \UricAcidRecordEntity.measuredAt, ascending: false)]
	) private var records: FetchedResults<UricAcidRecordEntity>

	@AppStorage(AppSettingsKey.preferredUnit) private var preferredUnitRawValue = UricUnit.umolL.rawValue
	@AppStorage(AppSettingsKey.userGender) private var userGenderRawValue = UserGender.male.rawValue
	@AppStorage(AppSettingsKey.targetEnabled) private var targetEnabled = false
	@AppStorage(AppSettingsKey.targetValue) private var targetValue: Double = 420
	@AppStorage(AppSettingsKey.iCloudEnabled) private var iCloudEnabled = false
	@AppStorage(AppSettingsKey.appLanguage) private var appLanguageRawValue = AppLanguage.simplifiedChinese.rawValue

	@State private var exportRange: TimeRange = .days90
	@State private var exportURL: URL?
	@State private var exportError: String?
	@State private var showingRestartHint = false
	@State private var showingHiddenSettings = false
	@State private var versionTapCount = 0
	@State private var lastPreferredUnitRawValue: String = UricUnit.umolL.rawValue

	init() {}

	enum FocusField: Hashable {
		case targetValue
	}

	var body: some View {
		ScrollView {
			VStack(spacing: 20) {
				// 偏好设置
				preferencesCard
				
				// 导出设置
				exportCard
				
				// 关于
				aboutCard
			}
			.padding()
		}
		.contentShape(Rectangle())
		.onTapGesture {
			focusedField = nil
		}
		.background(Color(.systemGroupedBackground))
		.navigationTitle("设置")
		.sheet(isPresented: $showingHiddenSettings) {
			HiddenSettingsView()
		}
			.alert("需要重启", isPresented: $showingRestartHint) {
				Button("知道了") {
					Analytics.track("icloud_restart_hint_acknowledged")
				}
		} message: {
			Text("iCloud 同步开关切换后，建议杀掉 App 重启一次。")
		}
		.onAppear {
			lastPreferredUnitRawValue = preferredUnitRawValue
		}
			.onChange(of: preferredUnitRawValue) { _, newValue in
				Analytics.track("preferred_unit_changed", properties: ["unit": newValue])
				let oldUnit = UricUnit(rawValue: lastPreferredUnitRawValue) ?? .umolL
				let newUnit = UricUnit(rawValue: newValue) ?? .umolL
				if oldUnit != newUnit {
					targetValue = UricUnit.convert(value: targetValue, from: oldUnit, to: newUnit)
					lastPreferredUnitRawValue = newValue
				}
			}
			.onChange(of: userGenderRawValue) { _, _ in
				Analytics.track("gender_setting_changed")
			}
			.onChange(of: targetEnabled) { _, _ in
				Analytics.track("target_setting_toggled")
			}
			.onChange(of: exportRange) { _, newValue in
				Analytics.track("export_range_changed", properties: ["range": newValue.rawValue])
			}
	}
	
	// MARK: - 偏好设置卡片
	private var preferencesCard: some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack {
				Image(systemName: "gearshape.fill")
					.font(.title3)
					.foregroundStyle(.blue)
				Text("偏好设置")
					.font(.system(size: 17, weight: .semibold))
				Spacer()
			}
			
			VStack(spacing: 0) {
				HStack(spacing: 12) {
					SettingIconView(icon: "globe", color: .teal)

					VStack(alignment: .leading, spacing: 4) {
						Text("应用语言")
							.font(.system(size: 16))
						Text("选择应用界面使用的语言")
							.font(.caption)
							.foregroundStyle(.secondary)
					}

					Spacer()

					Picker("语言", selection: $appLanguageRawValue) {
						ForEach(AppLanguage.allCases) { language in
							Text(language.displayName).tag(language.rawValue)
						}
					}
					.pickerStyle(.menu)
					.labelsHidden()
				}
				.padding(.vertical, 12)
				.onChange(of: appLanguageRawValue) { _, newValue in
					Analytics.track("app_language_changed", properties: ["language": newValue])
					persistence.refreshLocalizedStatus()
				}

				Divider()
					.padding(.leading, 44)

				// 单位选择
				HStack(spacing: 12) {
					SettingIconView(icon: "ruler.fill", color: .blue)
					
					VStack(alignment: .leading, spacing: 4) {
						Text("测量单位")
							.font(.system(size: 16))
						Text("选择尿酸值的显示单位")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					
					Spacer()
					
					Picker("单位", selection: $preferredUnitRawValue) {
						ForEach(UricUnit.allCases) { unit in
							Text(unit.displayName).tag(unit.rawValue)
						}
					}
					.pickerStyle(.menu)
					.labelsHidden()
				}
				.padding(.vertical, 12)
				
				Divider()
					.padding(.leading, 44)
				
				// 性别选择
				HStack(spacing: 12) {
					SettingIconView(icon: "person.fill", color: .pink)
					
					VStack(alignment: .leading, spacing: 4) {
						Text("性别")
							.font(.system(size: 16))
						Text("用于显示对应的参考范围")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					
					Spacer()
					
					Picker("性别", selection: $userGenderRawValue) {
						ForEach(UserGender.allCases) { gender in
							Text(gender.displayName).tag(gender.rawValue)
						}
					}
					.pickerStyle(.menu)
					.labelsHidden()
				}
				.padding(.vertical, 12)
				
				Divider()
					.padding(.leading, 44)
				
				// 目标值开关
				HStack(spacing: 12) {
					SettingIconView(icon: "target", color: .orange)
					
					VStack(alignment: .leading, spacing: 4) {
						Text("启用目标值")
							.font(.system(size: 16))
						Text("设置并追踪尿酸目标值")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					
					Spacer()
					
					Toggle("", isOn: $targetEnabled)
					.labelsHidden()
				}
				.padding(.vertical, 12)
				
				// 目标值输入
				if targetEnabled {
					Divider()
						.padding(.leading, 44)
					
					HStack(spacing: 12) {
						SettingIconView(icon: "number", color: .green)
						
						VStack(alignment: .leading, spacing: 4) {
							Text("目标数值")
								.font(.system(size: 16))
							Text("理想尿酸值上限")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						
						Spacer()
						
						HStack(spacing: 4) {
							TextField("", value: $targetValue, format: .number)
								.keyboardType(.decimalPad)
							.focused($focusedField, equals: .targetValue)
								.multilineTextAlignment(.trailing)
								.frame(width: 60)
							
							Text(UricUnit(rawValue: preferredUnitRawValue)?.displayName ?? "μmol/L")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
					}
					.padding(.vertical, 12)
				}
			}
		}
		.padding()
		.background(
			RoundedRectangle(cornerRadius: 16)
				.fill(Color(.secondarySystemGroupedBackground))
		)
		.shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
	}
	
	// MARK: - 导出卡片
	private var exportCard: some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack {
				Image(systemName: "square.and.arrow.up.fill")
					.font(.title3)
					.foregroundStyle(.green)
				Text("数据导出")
					.font(.system(size: 17, weight: .semibold))
				Spacer()
			}
			
			VStack(spacing: 0) {
				// 导出范围
				HStack(spacing: 12) {
					SettingIconView(icon: "calendar", color: .purple)
					
					VStack(alignment: .leading, spacing: 4) {
						Text("导出范围")
							.font(.system(size: 16))
						Text("选择要导出的时间范围")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					
					Spacer()
					
					Picker("范围", selection: $exportRange) {
						ForEach(TimeRange.allCases) { range in
							Text(range.displayName).tag(range)
						}
					}
					.pickerStyle(.menu)
					.labelsHidden()
				}
				.padding(.vertical, 12)
				
				Divider()
					.padding(.leading, 44)
				
				// 导出按钮
				Button(action: exportCSV) {
					HStack(spacing: 12) {
						SettingIconView(icon: "doc.text", color: .cyan)
						
						VStack(alignment: .leading, spacing: 4) {
							Text("导出 CSV 文件")
								.font(.system(size: 16))
								.foregroundStyle(.primary)
							Text("生成可分享的 CSV 文件")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						
						Spacer()
						
						Image(systemName: "chevron.right")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
				.padding(.vertical, 12)
				
				// 分享链接
				if let exportURL {
					Divider()
						.padding(.leading, 44)
					
					ShareLink(item: exportURL) {
						HStack(spacing: 12) {
							SettingIconView(icon: "square.and.arrow.up", color: .indigo)
							
							VStack(alignment: .leading, spacing: 4) {
								Text("分享 CSV 文件")
									.font(.system(size: 16))
								Text("通过系统分享发送")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							
							Spacer()
							
							Image(systemName: "chevron.right")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						.simultaneousGesture(TapGesture().onEnded {
							Analytics.track("csv_share_tapped")
						})
					}
					.padding(.vertical, 12)
				}
				
				// 错误提示
				if let exportError {
					Divider()
						.padding(.leading, 44)
					
					HStack(spacing: 12) {
						SettingIconView(icon: "exclamationmark.triangle", color: .red)
						
						Text(exportError)
							.font(.system(size: 14))
							.foregroundStyle(.red)
					}
					.padding(.vertical, 12)
				}
			}
		}
		.padding()
		.background(
			RoundedRectangle(cornerRadius: 16)
				.fill(Color(.secondarySystemGroupedBackground))
		)
		.shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
	}
	
	// MARK: - 关于卡片
	private var aboutCard: some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack {
				Image(systemName: "info.circle.fill")
					.font(.title3)
					.foregroundStyle(.indigo)
				Text("关于")
					.font(.system(size: 17, weight: .semibold))
				Spacer()
			}
			
			VStack(spacing: 0) {
				// iCloud 同步开关
				VStack(spacing: 0) {
					HStack(spacing: 12) {
						SettingIconView(icon: iCloudEnabled ? "icloud.fill" : "icloud.slash", color: iCloudEnabled ? .blue : .secondary)
						
						VStack(alignment: .leading, spacing: 4) {
							Text("iCloud 同步")
								.font(.system(size: 16))
							Text(iCloudEnabled ? persistence.iCloudStatus : L10n.string("当前仅本地存储"))
								.font(.caption)
								.foregroundStyle(iCloudStatusColor)
								.fixedSize(horizontal: false, vertical: true)
						}
						
						Spacer()
						
						if persistence.isSyncing {
							ProgressView()
								.scaleEffect(0.8)
						}
						
						Toggle("", isOn: $iCloudEnabled)
							.labelsHidden()
							.onChange(of: iCloudEnabled) { _, _ in
								Analytics.track("icloud_sync_toggled")
								showingRestartHint = true
							}
					}
					.padding(.vertical, 12)
				}
				.padding(.vertical, 12)
				
				Divider()
					.padding(.leading, 44)
				
				// 版本信息
				HStack(spacing: 12) {
					SettingIconView(icon: "v.square", color: .secondary)
					
					VStack(alignment: .leading, spacing: 4) {
						Text("版本")
							.font(.system(size: 16))
						Text("UricLog v1.0")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					
					Spacer()
				}
				.padding(.vertical, 12)
				.contentShape(Rectangle())
				.onTapGesture {
					versionTapCount += 1
					if versionTapCount >= 5 {
						versionTapCount = 0
						showingHiddenSettings = true
					}
				}
			}
		}
		.padding()
		.background(
			RoundedRectangle(cornerRadius: 16)
				.fill(Color(.secondarySystemGroupedBackground))
		)
		.shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
	}

	private func exportCSV() {
		Analytics.track("csv_export_tapped", properties: ["range": exportRange.rawValue])
		exportError = nil
		let preferredUnit = UricUnit(rawValue: preferredUnitRawValue) ?? .umolL
		let filtered = filterRecords(records: Array(records), range: exportRange)
		do {
			exportURL = try CSVExporter.export(records: filtered, preferredUnit: preferredUnit)
			Analytics.track("csv_export_succeeded")
		} catch {
			exportError = error.localizedDescription
			Analytics.track("csv_export_failed")
		}
	}

	private var iCloudStatusColor: Color {
		guard iCloudEnabled else { return .secondary }
		if persistence.iCloudSyncFailed { return .red }
		return persistence.isSyncing ? .blue : .green
	}

	private func filterRecords(records: [UricAcidRecordEntity], range: TimeRange) -> [UricAcidRecordEntity] {
		guard let start = range.startDate() else { return records }
		return records.filter { $0.measuredAt >= start }
	}
}

private struct HiddenSettingsView: View {
	@Environment(\.dismiss) private var dismiss
	@AppStorage(AppSettingsKey.adProviderOverride) private var adProviderRawValue = AdProviderPreference.automatic.rawValue
	@State private var showingPrivacyResetConfirmation = false
	@State private var showingAdResetConfirmation = false
	@State private var showingAdMobPrivacyResetConfirmation = false

	var body: some View {
		NavigationStack {
			List {
				Section {
					Picker("广告提供方", selection: $adProviderRawValue) {
						ForEach(AdProviderPreference.allCases) { provider in
							Text(provider.displayName).tag(provider.rawValue)
						}
					}
					.pickerStyle(.segmented)
				} header: {
					Text("广告提供方测试")
				} footer: {
					Text("默认模式：中国大陆 App Store 使用友盟，其他地区使用 AdMob。切换后请重新启动 App。")
				}

				Section {
					Button {
						showingPrivacyResetConfirmation = true
					} label: {
						Label("重置隐私授权", systemImage: "hand.raised")
					}

					Button {
						showingAdResetConfirmation = true
					} label: {
						Label("重置广告展示", systemImage: "rectangle.badge.xmark")
					}

					#if DEBUG
					Button {
						showingAdMobPrivacyResetConfirmation = true
					} label: {
						Label("测试 AdMob 隐私弹窗", systemImage: "hand.raised.square")
					}
					#endif
				} footer: {
					Text("重置后请彻底关闭并重新打开 App。尿酸记录和设置不会被删除。")
				}
			}
			.navigationTitle("内部设置")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("完成") { dismiss() }
				}
			}
			.confirmationDialog(
				"确认重置隐私授权？",
				isPresented: $showingPrivacyResetConfirmation,
				titleVisibility: .visible
			) {
				Button("重置隐私授权", role: .destructive) {
					UserDefaults.standard.removeObject(forKey: AppSettingsKey.privacyConsentGranted)
					UserDefaults.standard.removeObject(forKey: AppSettingsKey.privacyConsentChoiceMade)
					dismiss()
				}
			}
			.confirmationDialog(
				"下次启动时模拟欧洲地区并显示 AdMob 隐私弹窗？",
				isPresented: $showingAdMobPrivacyResetConfirmation,
				titleVisibility: .visible
			) {
				Button("重置并退出设置", role: .destructive) {
					adProviderRawValue = AdProviderPreference.admob.rawValue
					AppOpenAdManager.shared.resetAdMobPrivacyConsentForTesting()
					dismiss()
				}
			}
			.confirmationDialog(
				"确认重置今日广告展示记录？",
				isPresented: $showingAdResetConfirmation,
				titleVisibility: .visible
			) {
				Button("重置广告展示", role: .destructive) {
					AppOpenAdManager.shared.resetDailyExposure()
					dismiss()
				}
			}
		}
	}
}

// MARK: - 设置图标视图
private struct SettingIconView: View {
	let icon: String
	let color: Color
	
	var body: some View {
		Image(systemName: icon)
			.font(.system(size: 16, weight: .semibold))
			.foregroundStyle(color)
			.frame(width: 32, height: 32)
			.background(
				RoundedRectangle(cornerRadius: 8)
					.fill(color.opacity(0.15))
			)
	}
}
