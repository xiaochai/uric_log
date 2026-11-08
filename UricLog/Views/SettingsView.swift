import SwiftUI
import CoreData
import UIKit
import UniformTypeIdentifiers

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
	@AppStorage(AppSettingsKey.appLanguage) private var appLanguageRawValue = AppLanguage.english.rawValue
	@AppStorage(AppSettingsKey.measurementReminderEnabled) private var reminderEnabled = false
	@AppStorage(AppSettingsKey.measurementReminderWeekdays) private var reminderWeekdaysRawValue = "2,4,6"
	@AppStorage(AppSettingsKey.measurementReminderHour) private var reminderHour = 9
	@AppStorage(AppSettingsKey.measurementReminderMinute) private var reminderMinute = 0

	@State private var exportRange: TimeRange = .days90
	@State private var exportURL: URL?
	@State private var csvShare: CSVShareItem?
	@State private var exportError: String?
	@State private var showingCSVImporter = false
	@State private var isValidatingImport = false
	@State private var isImporting = false
	@State private var pendingImport: CSVImportPreview?
	@State private var importSaveError: String?
	@State private var importNotice: CSVImportNotice?
	@State private var completedImportCount: Int?
	@State private var showingRestartHint = false
	@State private var lastPreferredUnitRawValue: String = UricUnit.umolL.rawValue
	@State private var showingNotificationPermissionAlert = false

	init() {}

	enum FocusField: Hashable {
		case targetValue
	}

	var body: some View {
		ScrollView {
			VStack(spacing: 20) {
				// Preferences
				preferencesCard

				reminderCard
				
				// Export settings
				exportCard
					.disabled(isValidatingImport || isImporting)

				importCard
				
				// About
				aboutCard
			}
			.padding()
		}
		.contentShape(Rectangle())
		.onTapGesture {
			focusedField = nil
		}
		.background(Color(.systemGroupedBackground))
		.navigationTitle("TAB_SETTINGS")
		.sheet(item: $csvShare) { item in
			CSVShareSheet(url: item.url)
		}
		.fileImporter(
			isPresented: $showingCSVImporter,
			allowedContentTypes: [.commaSeparatedText],
			allowsMultipleSelection: false,
			onCompletion: prepareCSVImport
		)
		.sheet(item: $pendingImport, onDismiss: importReviewDismissed) { preview in
			CSVImportReviewSheet(
				count: preview.document.records.count,
				isImporting: isImporting,
				saveError: $importSaveError,
				onImport: performCSVImport
			)
		}
		.alert(
			importNotice?.title ?? "",
			isPresented: Binding(
				get: { importNotice != nil },
				set: { if !$0 { importNotice = nil } }
			)
		) {
			Button("OK", role: .cancel) { importNotice = nil }
		} message: {
			Text(importNotice?.message ?? "")
		}
		.alert("RESTART_RECOMMENDED", isPresented: $showingRestartHint) {
				Button("OK") {
					Analytics.track("icloud_restart_hint_acknowledged")
				}
		} message: {
			Text("ICLOUD_RESTART_MESSAGE")
		}
		.alert("REMINDER_ENABLE_ERROR", isPresented: $showingNotificationPermissionAlert) {
			Button("OK", role: .cancel) {}
			Button("OPEN_SYSTEM_SETTINGS") {
				if let url = URL(string: UIApplication.openSettingsURLString) {
					UIApplication.shared.open(url)
				}
			}
		} message: {
			Text("NOTIFICATION_PERMISSION_HINT")
		}
		.onAppear {
			lastPreferredUnitRawValue = preferredUnitRawValue
		}
			.onChange(of: preferredUnitRawValue) { _, newValue in
				Analytics.track("preferred_unit_changed", properties: ["unit": newValue])
				let oldUnit = UricUnit(rawValue: lastPreferredUnitRawValue) ?? .umolL
				let newUnit = UricUnit(rawValue: newValue) ?? .umolL
				if oldUnit != newUnit {
					targetValue = UricUnit.convertWithoutRounding(value: targetValue, from: oldUnit, to: newUnit)
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
	
	// MARK: - Preferences card
	private var preferencesCard: some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack {
				Image(systemName: "gearshape.fill")
					.font(.title3)
					.foregroundStyle(.blue)
				Text("PREFERENCES")
					.font(.system(size: 17, weight: .semibold))
				Spacer()
			}
			
			VStack(spacing: 0) {
				HStack(spacing: 12) {
					SettingIconView(icon: "globe", color: .teal)

					VStack(alignment: .leading, spacing: 4) {
						Text("APP_LANGUAGE")
							.font(.system(size: 16))
						Text("APP_LANGUAGE_DESCRIPTION")
							.font(.caption)
							.foregroundStyle(.secondary)
					}

					Spacer()

					Picker("LANGUAGE", selection: $appLanguageRawValue) {
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
					rescheduleReminder()
				}

				Divider()
					.padding(.leading, 44)

				// Unit selection
				HStack(spacing: 12) {
					SettingIconView(icon: "ruler.fill", color: .blue)
					
					VStack(alignment: .leading, spacing: 4) {
						Text("MEASUREMENT_UNIT")
							.font(.system(size: 16))
						Text("MEASUREMENT_UNIT_DESCRIPTION")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					
					Spacer()
					
					Picker("UNIT", selection: $preferredUnitRawValue) {
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
				
				// Gender selection
				HStack(spacing: 12) {
					SettingIconView(icon: "person.fill", color: .pink)
					
					VStack(alignment: .leading, spacing: 4) {
						Text("SEX")
							.font(.system(size: 16))
						Text("SEX_DESCRIPTION")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					
					Spacer()
					
					Picker("SEX", selection: $userGenderRawValue) {
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
				
				// Target value toggle
				HStack(spacing: 12) {
					SettingIconView(icon: "target", color: .orange)
					
					VStack(alignment: .leading, spacing: 4) {
						Text("ENABLE_TARGET")
							.font(.system(size: 16))
						Text("TARGET_DESCRIPTION")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					
					Spacer()
					
					Toggle("", isOn: $targetEnabled)
					.labelsHidden()
				}
				.padding(.vertical, 12)
				
				// Target value input
				if targetEnabled {
					Divider()
						.padding(.leading, 44)
					
					HStack(spacing: 12) {
						SettingIconView(icon: "number", color: .green)
						
						VStack(alignment: .leading, spacing: 4) {
							Text("TARGET_VALUE")
								.font(.system(size: 16))
							Text("TARGET_VALUE_DESCRIPTION")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						
						Spacer()
						
						HStack(spacing: 4) {
							TextField(
								"",
								value: $targetValue,
								format: .number.locale(AppLanguage.selected.locale).precision(.fractionLength(2))
							)
								.keyboardType(.decimalPad)
							.focused($focusedField, equals: .targetValue)
								.multilineTextAlignment(.trailing)
								.frame(width: 90)
							
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

	private var reminderCard: some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack {
				Image(systemName: "bell.badge.fill")
					.font(.title3)
					.foregroundStyle(.orange)
				Text("MEASUREMENT_REMINDERS")
					.font(.system(size: 17, weight: .semibold))
				Spacer()
			}

			VStack(spacing: 0) {
				HStack(spacing: 12) {
					SettingIconView(icon: "bell.fill", color: .orange)
					VStack(alignment: .leading, spacing: 4) {
						Text("SCHEDULED_REMINDERS")
							.font(.system(size: 16))
						Text("REMINDER_SCHEDULE_DESCRIPTION")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					Spacer()
					Toggle("", isOn: $reminderEnabled)
						.labelsHidden()
						.onChange(of: reminderEnabled) { _, enabled in
							updateReminder(enabled: enabled)
						}
				}
				.padding(.vertical, 12)

				if reminderEnabled {
					Divider().padding(.leading, 44)

					VStack(alignment: .leading, spacing: 12) {
						Text("REMINDER_DAYS")
							.font(.subheadline)
							.foregroundStyle(.secondary)
						HStack(spacing: 8) {
							ForEach(reminderDayOptions, id: \.weekday) { option in
								Button {
									toggleReminderDay(option.weekday)
								} label: {
									Text(option.title)
										.font(.subheadline.weight(.medium))
										.frame(maxWidth: .infinity, minHeight: 36)
										.background(selectedReminderWeekdays.contains(option.weekday) ? Color.blue : Color(.tertiarySystemFill))
										.foregroundStyle(selectedReminderWeekdays.contains(option.weekday) ? .white : .primary)
										.clipShape(RoundedRectangle(cornerRadius: 8))
								}
								.buttonStyle(.plain)
							}
						}
					}
					.padding(.vertical, 12)

					Divider().padding(.leading, 44)

					HStack(spacing: 12) {
						SettingIconView(icon: "clock.fill", color: .blue)
						Text("REMINDER_TIME")
							.font(.system(size: 16))
						Spacer()
						DatePicker("", selection: reminderTime, displayedComponents: .hourAndMinute)
							.labelsHidden()
							.onChange(of: reminderHour) { _, _ in rescheduleReminder() }
							.onChange(of: reminderMinute) { _, _ in rescheduleReminder() }
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

	private var reminderDayOptions: [(weekday: Int, title: String)] {
		[(2, "WEEKDAY_MON"), (3, "WEEKDAY_TUE"), (4, "WEEKDAY_WED"), (5, "WEEKDAY_THU"), (6, "WEEKDAY_FRI"), (7, "WEEKDAY_SAT"), (1, "WEEKDAY_SUN")]
			.map { ($0.0, L10n.string($0.1)) }
	}

	private var selectedReminderWeekdays: Set<Int> {
		Set(reminderWeekdaysRawValue.split(separator: ",").compactMap { Int($0) })
	}

	private var reminderTime: Binding<Date> {
		Binding(
			get: {
				Calendar.current.date(from: DateComponents(hour: reminderHour, minute: reminderMinute)) ?? Date()
			},
			set: { date in
				let components = Calendar.current.dateComponents([.hour, .minute], from: date)
				reminderHour = components.hour ?? 9
				reminderMinute = components.minute ?? 0
			}
		)
	}

	private func toggleReminderDay(_ weekday: Int) {
		var weekdays = selectedReminderWeekdays
		if weekdays.contains(weekday) {
			guard weekdays.count > 1 else { return }
			weekdays.remove(weekday)
		} else {
			weekdays.insert(weekday)
		}
		reminderWeekdaysRawValue = weekdays.sorted().map(String.init).joined(separator: ",")
		rescheduleReminder()
	}

	private func updateReminder(enabled: Bool) {
		Task {
			if enabled {
				guard await MeasurementReminderManager.requestAuthorization() else {
					reminderEnabled = false
					showingNotificationPermissionAlert = true
					Analytics.track("measurement_reminder_permission_denied")
					return
				}
				await MeasurementReminderManager.schedule(
					weekdays: selectedReminderWeekdays,
					hour: reminderHour,
					minute: reminderMinute
				)
				Analytics.track("measurement_reminder_enabled")
			} else {
				await MeasurementReminderManager.cancel()
				Analytics.track("measurement_reminder_disabled")
			}
		}
	}

	private func rescheduleReminder() {
		guard reminderEnabled else { return }
		Task {
			await MeasurementReminderManager.schedule(
				weekdays: selectedReminderWeekdays,
				hour: reminderHour,
				minute: reminderMinute
			)
			Analytics.track("measurement_reminder_schedule_changed", properties: [
				"weekdays": reminderWeekdaysRawValue,
				"hour": reminderHour,
				"minute": reminderMinute,
			])
		}
	}
	
	// MARK: - Export card
	private var exportCard: some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack {
				Image(systemName: "square.and.arrow.up.fill")
					.font(.title3)
					.foregroundStyle(.green)
				Text("DATA_EXPORT")
					.font(.system(size: 17, weight: .semibold))
				Spacer()
			}
			
			VStack(spacing: 0) {
				// Export range
				HStack(spacing: 12) {
					SettingIconView(icon: "calendar", color: .purple)
					
					VStack(alignment: .leading, spacing: 4) {
						Text("EXPORT_RANGE")
							.font(.system(size: 16))
						Text("EXPORT_RANGE_DESCRIPTION")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					
					Spacer()
					
					Picker("RANGE", selection: $exportRange) {
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
				
				// Export button
				Button(action: exportCSV) {
					HStack(spacing: 12) {
						SettingIconView(icon: "doc.text", color: .cyan)
						
						VStack(alignment: .leading, spacing: 4) {
							Text("EXPORT_CSV")
								.font(.system(size: 16))
								.foregroundStyle(.primary)
							Text("EXPORT_CSV_DESCRIPTION")
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
				.accessibilityIdentifier("export-csv-button")
				
				// Share link
				if let exportURL {
					Divider()
						.padding(.leading, 44)
					
					Button {
						shareCSV(at: exportURL)
					} label: {
						HStack(spacing: 12) {
							SettingIconView(icon: "square.and.arrow.up", color: .indigo)
							
							VStack(alignment: .leading, spacing: 4) {
								Text("SHARE_CSV")
									.font(.system(size: 16))
								Text("SHARE_CSV_DESCRIPTION")
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
					.accessibilityIdentifier("share-csv-button")
				}
				
				// Error message
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
	
	// MARK: - Import card
	private var importCard: some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack {
				Image(systemName: "square.and.arrow.down.fill")
					.font(.title3)
					.foregroundStyle(.blue)
				Text("DATA_IMPORT")
					.font(.system(size: 17, weight: .semibold))
				Spacer()
			}
			Button {
				focusedField = nil
				importSaveError = nil
				showingCSVImporter = true
			} label: {
				HStack(spacing: 12) {
					SettingIconView(icon: "square.and.arrow.down", color: .blue)
					VStack(alignment: .leading, spacing: 4) {
						Text(LocalizedStringKey(isValidatingImport ? "IMPORT_CSV_PROGRESS" : "IMPORT_CSV"))
							.font(.system(size: 16))
							.foregroundStyle(.primary)
						Text("IMPORT_CSV_DESCRIPTION")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					Spacer()
					if isValidatingImport {
						ProgressView()
					} else {
						Image(systemName: "chevron.right")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
				.padding(.vertical, 12)
			}
			.disabled(isValidatingImport || isImporting)
			.accessibilityIdentifier("import-csv-button")
		}
		.padding()
		.background(
			RoundedRectangle(cornerRadius: 16)
				.fill(Color(.secondarySystemGroupedBackground))
		)
		.shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
	}

	// MARK: - About card
	private var aboutCard: some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack {
				Image(systemName: "info.circle.fill")
					.font(.title3)
					.foregroundStyle(.indigo)
				Text("ABOUT")
					.font(.system(size: 17, weight: .semibold))
				Spacer()
			}
			
			VStack(spacing: 0) {
				// iCloud sync toggle
				VStack(spacing: 0) {
					HStack(spacing: 12) {
						SettingIconView(icon: iCloudEnabled ? "icloud.fill" : "icloud.slash", color: iCloudEnabled ? .blue : .secondary)
						
						VStack(alignment: .leading, spacing: 4) {
							Text("ICLOUD_SYNC")
								.font(.system(size: 16))
							Text(iCloudEnabled ? persistence.iCloudStatus : L10n.string("LOCAL_STORAGE_ONLY"))
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

				// Version information
				HStack(spacing: 12) {
					SettingIconView(icon: "v.square", color: .secondary)
					
					VStack(alignment: .leading, spacing: 4) {
						Text("APP_VERSION")
							.font(.system(size: 16))
						Text(appVersionText)
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

	private var appVersionText: String {
		let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
		return "v\(version)"
	}

	private func exportCSV() {
		Analytics.track("csv_export_tapped", properties: ["range": exportRange.rawValue])
		focusedField = nil
		exportError = nil
		exportURL = nil
		csvShare = nil
		let preferredUnit = UricUnit(rawValue: preferredUnitRawValue) ?? .umolL
		let filtered = filterRecords(records: Array(records), range: exportRange)
		do {
			let url = try CSVExporter.export(records: filtered, preferredUnit: preferredUnit)
			exportURL = url
			Analytics.track("csv_export_succeeded")
			shareCSV(at: url)
		} catch {
			exportError = error.localizedDescription
			Analytics.track("csv_export_failed")
		}
	}

	private func shareCSV(at url: URL) {
		focusedField = nil
		csvShare = CSVShareItem(url: url)
		Analytics.track("csv_share_tapped")
	}

	private func prepareCSVImport(_ result: Result<[URL], Error>) {
		switch result {
		case .success(let urls):
			guard let url = urls.first else { return }
			isValidatingImport = true
			importSaveError = nil
			Task { @MainActor in
				do {
					let document = try await Task.detached(priority: .userInitiated) {
						try CSVImportFileReader.read(url)
					}.value
					pendingImport = CSVImportPreview(document: document)
				} catch {
					importNotice = CSVImportNotice(
						title: L10n.string("IMPORT_FAILURE_TITLE"), message: error.localizedDescription
					)
				}
				isValidatingImport = false
			}
		case .failure(let error):
			guard (error as NSError).code != NSUserCancelledError else { return }
			importNotice = CSVImportNotice(
				title: L10n.string("IMPORT_FAILURE_TITLE"), message: L10n.string("CSV_IMPORT_READ_ERROR")
			)
		}
	}

	private func performCSVImport(_ mode: CSVImportMode) {
		guard let document = pendingImport?.document, !isImporting else { return }
		isImporting = true
		importSaveError = nil
		Task { @MainActor in
			do {
				completedImportCount = try await CSVImportStore.apply(document, mode: mode, to: persistence.container)
				pendingImport = nil
			} catch {
				importSaveError = error.localizedDescription
			}
			isImporting = false
		}
	}

	private func importReviewDismissed() {
		importSaveError = nil
		guard let count = completedImportCount else { return }
		completedImportCount = nil
		importNotice = CSVImportNotice(
			title: L10n.string("IMPORT_SUCCESS_TITLE"), message: L10n.format("IMPORT_SUCCESS_MESSAGE", count)
		)
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

private struct CSVImportPreview: Identifiable {
	let id = UUID()
	let document: CSVImportDocument
}

private struct CSVImportNotice {
	let title: String
	let message: String
}

private struct CSVImportReviewSheet: View {
	@Environment(\.dismiss) private var dismiss
	@State private var confirmingReplacement = false
	let count: Int
	let isImporting: Bool
	@Binding var saveError: String?
	let onImport: (CSVImportMode) -> Void

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 24) {
					Image(systemName: "doc.badge.checkmark")
						.font(.system(size: 44))
						.foregroundStyle(.green)
					Text(L10n.format("IMPORT_MODE_MESSAGE", count))
						.multilineTextAlignment(.center)
					if isImporting {
						ProgressView("IMPORT_CSV_SAVING")
							.accessibilityIdentifier("csv-import-progress")
					} else {
						Button("IMPORT_APPEND") { onImport(.append) }
							.buttonStyle(.borderedProminent)
							.accessibilityIdentifier("csv-import-append")
						Button("IMPORT_REPLACE", role: .destructive) { confirmingReplacement = true }
							.buttonStyle(.bordered)
							.accessibilityIdentifier("csv-import-replace")
					}
				}
				.padding(24)
			}
			.navigationTitle("IMPORT_MODE_TITLE")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("CANCEL") { dismiss() }
						.disabled(isImporting)
						.accessibilityIdentifier("csv-import-cancel")
				}
			}
			.alert("IMPORT_REPLACE_TITLE", isPresented: $confirmingReplacement) {
				Button("CANCEL", role: .cancel) {}
				Button("IMPORT_REPLACE", role: .destructive) { onImport(.replace) }
					.accessibilityIdentifier("csv-import-confirm-replace")
			} message: {
				Text(L10n.format("IMPORT_REPLACE_MESSAGE", count))
			}
			.alert(
				"IMPORT_FAILURE_TITLE",
				isPresented: Binding(
					get: { saveError != nil },
					set: { if !$0 { saveError = nil } }
				)
			) {
				Button("OK", role: .cancel) { saveError = nil }
			} message: {
				Text(saveError ?? "")
			}
		}
		.interactiveDismissDisabled(isImporting)
	}
}

private enum CSVImportFileReader {
	private enum ReadError: LocalizedError {
		case unreadable
		var errorDescription: String? { L10n.string("CSV_IMPORT_READ_ERROR") }
	}

	static func read(_ url: URL) throws -> CSVImportDocument {
		let hasAccess = url.startAccessingSecurityScopedResource()
		defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
		var coordinationError: NSError?
		var result: Result<CSVImportDocument, Error>?
		NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinatedURL in
			result = Result {
				let data: Data
				do {
					data = try Data(contentsOf: coordinatedURL)
				} catch {
					throw ReadError.unreadable
				}
				return try CSVImporter.parse(data: data)
			}
		}
		guard coordinationError == nil, let result else { throw ReadError.unreadable }
		return try result.get()
	}
}

private struct CSVShareItem: Identifiable {
	let id = UUID()
	let url: URL
}

private struct CSVShareSheet: UIViewControllerRepresentable {
	let url: URL

	func makeUIViewController(context: Context) -> UIActivityViewController {
		UIActivityViewController(activityItems: [url], applicationActivities: nil)
	}

	func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Setting icon view
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
