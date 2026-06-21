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

	@State private var exportRange: TimeRange = .days90
	@State private var exportURL: URL?
	@State private var exportError: String?
	@State private var showingRestartHint = false
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
		.alert("需要重启", isPresented: $showingRestartHint) {
			Button("知道了") {}
		} message: {
			Text("iCloud 同步开关切换后，建议杀掉 App 重启一次。")
		}
		.onAppear {
			lastPreferredUnitRawValue = preferredUnitRawValue
		}
		.onChange(of: preferredUnitRawValue) { _, newValue in
			let oldUnit = UricUnit(rawValue: lastPreferredUnitRawValue) ?? .umolL
			let newUnit = UricUnit(rawValue: newValue) ?? .umolL
			if oldUnit != newUnit {
				targetValue = UricUnit.convert(value: targetValue, from: oldUnit, to: newUnit)
				lastPreferredUnitRawValue = newValue
			}
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
							Text(iCloudEnabled ? persistence.iCloudStatus : "当前仅本地存储")
								.font(.caption)
								.foregroundStyle(iCloudEnabled ? (persistence.isSyncing ? .blue : .green) : .secondary)
						}
						
						Spacer()
						
						if persistence.isSyncing {
							ProgressView()
								.scaleEffect(0.8)
						}
						
						Toggle("", isOn: $iCloudEnabled)
							.labelsHidden()
							.onChange(of: iCloudEnabled) { _, _ in
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
		exportError = nil
		let preferredUnit = UricUnit(rawValue: preferredUnitRawValue) ?? .umolL
		let filtered = filterRecords(records: Array(records), range: exportRange)
		do {
			exportURL = try CSVExporter.export(records: filtered, preferredUnit: preferredUnit)
		} catch {
			exportError = error.localizedDescription
		}
	}

	private func filterRecords(records: [UricAcidRecordEntity], range: TimeRange) -> [UricAcidRecordEntity] {
		guard let start = range.startDate() else { return records }
		return records.filter { $0.measuredAt >= start }
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
