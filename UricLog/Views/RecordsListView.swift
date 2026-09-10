import SwiftUI
import CoreData

struct RecordsListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \UricAcidRecordEntity.measuredAt, ascending: false)]
    ) private var records: FetchedResults<UricAcidRecordEntity>
	@AppStorage(AppSettingsKey.userGender) private var userGenderRawValue = UserGender.male.rawValue
	@AppStorage(AppSettingsKey.preferredUnit) private var preferredUnitRawValue = UricUnit.umolL.rawValue
	@AppStorage(AppSettingsKey.selectedTimeRange) private var timeRangeRawValue = TimeRange.days30.rawValue

    @State private var editorDestination: RecordEditorDestination?

    init() {}

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 时间范围选择器
                timeRangePicker
                
                // 记录列表
                recordsSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("尿酸记录")
	        .toolbar {
	            ToolbarItem(placement: .topBarTrailing) {
	                Button {
	                    Analytics.track("record_add_tapped")
	                    editorDestination = RecordEditorDestination(record: nil)
                } label: {
					Image(systemName: "plus.circle.fill")
						.font(.title3)
						.foregroundStyle(.blue)
                }
				.scaleEffect(1.3)
            }
        }
        .sheet(item: $editorDestination) { destination in
            NavigationStack {
                RecordEditorView(record: destination.record)
            }
        }
    }
    
	private var timeRangePicker: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Image(systemName: "calendar")
					.foregroundStyle(.blue)
				Text("时间范围")
					.font(.system(size: 17, weight: .semibold))
				Spacer()
			}
            
            Picker("范围", selection: timeRangeSelection) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.displayName).tag(range)
                }
            }
			.pickerStyle(.segmented)
			.onChange(of: timeRange) { _, newValue in
				Analytics.track("records_range_changed", properties: ["range": newValue.rawValue])
			}
        }
        .padding()
		.frame(minHeight: 108)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
    
    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
				Image(systemName: "list.bullet.clipboard")
					.foregroundStyle(.blue)
				Text("记录列表")
					.font(.system(size: 17, weight: .semibold))
                
                Spacer()
                
                Text(L10n.format("%d 条", filteredRecords.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.1))
                    )
            }
            .padding(.horizontal, 4)
            
            if filteredRecords.isEmpty {
                emptyStateView
            } else {
                LazyVStack(spacing: 12) {
					ForEach(filteredRecords.map(UricAcidRecordSnapshot.init(record:)), id: \.id) { snapshot in
						RecordCard(record: snapshot, displayUnit: preferredUnit, userGender: userGender) {
							edit(objectID: snapshot.id)
						} onDelete: {
							delete(objectID: snapshot.id)
						}
					}
                }
            }
        }
    }

	private var userGender: UserGender {
		UserGender(rawValue: userGenderRawValue) ?? .male
	}

	private var preferredUnit: UricUnit {
		UricUnit(rawValue: preferredUnitRawValue) ?? .umolL
	}

	private var timeRange: TimeRange {
		TimeRange(rawValue: timeRangeRawValue) ?? .days30
	}

	private var timeRangeSelection: Binding<TimeRange> {
		Binding(
			get: { timeRange },
			set: { timeRangeRawValue = $0.rawValue }
		)
	}
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "drop.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue.opacity(0.3))
            
            Text("暂无记录")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("点击右上角 + 添加第一条尿酸记录")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .stroke(Color.blue.opacity(0.1), lineWidth: 1)
        )
    }

    private var filteredRecords: [UricAcidRecordEntity] {
        guard let start = timeRange.startDate() else { return Array(records) }
        return records.filter { $0.measuredAt >= start }
    }

	private func edit(objectID: NSManagedObjectID) {
		if let record = try? viewContext.existingObject(with: objectID) as? UricAcidRecordEntity {
			Analytics.track("record_opened")
			editorDestination = RecordEditorDestination(record: record)
		}
	}

		private func delete(objectID: NSManagedObjectID) {
			if let record = try? viewContext.existingObject(with: objectID) as? UricAcidRecordEntity {
			viewContext.delete(record)
				try? viewContext.save()
				Analytics.track("record_deleted")
		}
	}
}

private struct RecordEditorDestination: Identifiable {
	let id = UUID()
	let record: UricAcidRecordEntity?
}

// MARK: - Record Card
struct UricAcidRecordSnapshot: Identifiable {
	let id: NSManagedObjectID
	let measuredAt: Date
	let value: Double
	let unit: UricUnit
	let note: String

	init(record: UricAcidRecordEntity) {
		self.id = record.objectID
		self.measuredAt = record.measuredAt
		self.value = record.value
		self.unit = record.unit
		self.note = record.note ?? ""
	}
}

struct RecordCard: View {
	let record: UricAcidRecordSnapshot
	let displayUnit: UricUnit
	let userGender: UserGender
    let onTap: () -> Void
    let onDelete: () -> Void
    
    @State private var showingDeleteConfirm = false
    
    var body: some View {
        Button(action: onTap) {
			VStack(alignment: .leading, spacing: 14) {
				HStack(alignment: .firstTextBaseline, spacing: 12) {
					HStack(spacing: 7) {
						Text(record.measuredAt.chineseShortDate)
							.font(.system(size: 17, weight: .semibold))
							.foregroundStyle(.primary)
							.lineLimit(1)
						Image(systemName: "clock")
							.font(.system(size: 16, weight: .medium))
						Text(record.measuredAt.chineseTime)
							.font(.system(size: 16, weight: .regular, design: .rounded))
					}
					.foregroundStyle(.secondary)

					Spacer(minLength: 8)

					HStack(alignment: .firstTextBaseline, spacing: 5) {
						Text(valueString)
							.font(.system(size: 31, weight: .bold, design: .rounded))
							.foregroundStyle(valueColor)
							.lineLimit(1)
							.minimumScaleFactor(0.65)
						Text(displayUnit.displayName)
							.font(.system(size: 14, weight: .medium))
							.foregroundStyle(.secondary)
					}
				}

				if !record.note.isEmpty {
					Text(note)
						.font(.system(size: 15))
						.foregroundStyle(.secondary)
						.lineLimit(2)
						.frame(maxWidth: .infinity, alignment: .leading)
				}
			}
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(valueColor.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
	        .contextMenu {
	            Button(role: .destructive) {
	                Analytics.track("record_delete_requested")
	                showingDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .alert("确认删除", isPresented: $showingDeleteConfirm) {
	            Button("取消", role: .cancel) {
	                Analytics.track("record_delete_cancelled")
	            }
	            Button("删除", role: .destructive) {
	                Analytics.track("record_delete_confirmed")
	                onDelete()
            }
        } message: {
            Text("这条记录将被永久删除，无法恢复。")
        }
    }
    
	private var note: String { record.note }
    
	private var valueString: String {
		displayValue.formatted(.number.precision(.fractionLength(0...4)))
	}

	private var displayValue: Double {
		UricUnit.convert(value: record.value, from: record.unit, to: displayUnit)
	}
    
    private var valueColor: Color {
        let value = record.value
		let umolValue = UricUnit.convert(value: value, from: record.unit, to: .umolL)
		let upper = userGender.normalRangeUpper
		if umolValue <= upper {
			return .green
		}
		let delta = umolValue - upper
		let maxDelta = 200.0
		let ratio = min(max(delta / maxDelta, 0), 1)
		let hue = 0.14 - (0.14 * ratio)
		return Color(hue: hue, saturation: 0.95, brightness: 0.95)
    }
}
