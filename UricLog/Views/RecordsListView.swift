import SwiftUI
import CoreData

struct RecordsListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \UricAcidRecordEntity.measuredAt, ascending: false)]
    ) private var records: FetchedResults<UricAcidRecordEntity>

    @State private var timeRange: TimeRange = .days30
    @State private var showingEditor = false
    @State private var editingRecord: UricAcidRecordEntity?

    init() {}

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 时间范围选择器
                timeRangePicker
                
                // 记录列表
                recordsSection
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("尿酸记录")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingRecord = nil
                    showingEditor = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                RecordEditorView(record: editingRecord)
            }
        }
    }
    
    private var timeRangePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("时间范围")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            
            Picker("范围", selection: $timeRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.displayName).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
    
    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("记录列表", systemImage: "list.bullet.clipboard")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(filteredRecords.count) 条")
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
                    ForEach(filteredRecords, id: \.objectID) { record in
                        RecordCard(record: record) {
                            editingRecord = record
                            showingEditor = true
                        } onDelete: {
                            delete(record)
                        }
                    }
                }
            }
        }
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

    private func delete(_ record: UricAcidRecordEntity) {
        viewContext.delete(record)
        try? viewContext.save()
    }
}

// MARK: - Record Card
struct RecordCard: View {
    let record: UricAcidRecordEntity
    let onTap: () -> Void
    let onDelete: () -> Void
    
    @State private var showingDeleteConfirm = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // 日期指示器
                dateIndicator
                
                // 分隔线
                Rectangle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 1, height: 50)
                
                // 数值信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(valueString)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(valueColor)
                        
                        Text(record.unit.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let note = record.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // 箭头指示
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
                showingDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .alert("确认删除", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("这条记录将被永久删除，无法恢复。")
        }
    }
    
    private var dateIndicator: some View {
        VStack(spacing: 2) {
            Text(record.measuredAt.chineseShortDate)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(record.measuredAt.chineseTime)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(width: 60)
    }
    
    private var valueString: String {
        String(format: "%.0f", record.value)
    }
    
    private var valueColor: Color {
        let value = record.value
        let umolValue = UricUnit.convert(value: value, from: record.unit, to: .umolL)
        
        if umolValue <= 360 {
            return .green
        } else if umolValue <= 420 {
            return .orange
        } else {
            return .red
        }
    }
}
