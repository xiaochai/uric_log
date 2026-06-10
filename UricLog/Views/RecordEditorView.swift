import SwiftUI
import CoreData

struct RecordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @AppStorage(AppSettingsKey.preferredUnit) private var preferredUnitRawValue = UricUnit.umolL.rawValue
    @AppStorage(AppSettingsKey.userGender) private var userGenderRawValue = UserGender.male.rawValue

    private let record: UricAcidRecordEntity?

    @State private var valueText: String = ""
    @State private var selectedUnit: UricUnit = .umolL
    @State private var measuredAt: Date = Date()
    @State private var note: String = ""
    @State private var showingExtremeConfirm = false
    @State private var showingReferenceInfo = false
    @State private var pendingSaveValue: Double?

    init(record: UricAcidRecordEntity?) {
        self.record = record
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 数值输入卡片
                valueInputCard
                
                // 参考范围卡片
                referenceRangeCard
                
                // 时间选择卡片
                timeSelectionCard
                
                // 备注卡片
                noteCard
                
                // 保存按钮
                saveButton
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(record == nil ? "新增记录" : "编辑记录")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .alert("数值看起来异常", isPresented: $showingExtremeConfirm) {
            Button("取消", role: .cancel) {
                pendingSaveValue = nil
            }
            Button("仍要保存", role: .destructive) {
                if let value = pendingSaveValue {
                    save(value: value)
                }
                pendingSaveValue = nil
            }
        } message: {
            Text("您输入的尿酸数值超出正常范围（50-1200 μmol/L），请确认是否正确。")
        }
        .sheet(isPresented: $showingReferenceInfo) {
            ReferenceInfoSheet()
        }
        .onAppear {
            selectedUnit = UricUnit(rawValue: preferredUnitRawValue) ?? .umolL
            if let record {
                measuredAt = record.measuredAt
                selectedUnit = record.unit
                valueText = String(format: "%.0f", record.value)
                note = record.note ?? ""
            }
        }
    }
    
    private var valueInputCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "drop.fill")
                    .foregroundStyle(.blue)
                    .font(.title2)
                
                Text("尿酸数值")
                    .font(.headline)
                
                Spacer()
            }
            
            HStack(spacing: 12) {
                TextField("输入数值", text: $valueText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .frame(height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.05))
                    )
                
                VStack(spacing: 8) {
                    ForEach(UricUnit.allCases) { unit in
                        Button {
                            selectedUnit = unit
                        } label: {
                            Text(unit.displayName)
                                .font(.caption)
                                .fontWeight(selectedUnit == unit ? .bold : .regular)
                                .foregroundStyle(selectedUnit == unit ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedUnit == unit ? Color.blue : Color(.systemGray5))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
    
    private var referenceRangeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.cyan)
                    .font(.title3)
                
                Text("参考范围")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    showingReferenceInfo = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
            
            // 当前性别对应的正常范围
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("您的正常范围（\(userGender.displayName)）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                
                Text(userGender.normalRangeText(unit: selectedUnit))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.cyan)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.cyan.opacity(0.08))
            )
            
            // 正常范围说明
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                
                Text("正常范围")
                    .font(.system(size: 15, weight: .medium))
                
                Spacer()
                
                Text(userGender.normalRangeText(unit: selectedUnit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
    
    private func referenceRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
            
            Text(title)
                .font(.system(size: 15, weight: .medium))
            
            Spacer()
            
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private func goutControlHint(umolValue: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.vertical, 4)
            
            Text("痛风控制目标")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("一般痛风")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("< 360 μmol/L")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(umolValue < 360 ? .green : .secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("有痛风石/频繁发作")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("< 300 μmol/L")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(umolValue < 300 ? .green : .secondary)
                }
                
                Spacer()
            }
        }
    }
    
    private var timeSelectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.blue)
                    .font(.title3)
                
                Text("测量时间")
                    .font(.headline)
                
                Spacer()
            }
            
            // 显示当前选择的时间（中文格式）
            Text(measuredAt.chineseDateTime)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            
            DatePicker("", selection: $measuredAt)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 180)
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
    
    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(.blue)
                    .font(.title3)
                
                Text("备注")
                    .font(.headline)
                
                Spacer()
                
                Text("可选")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            TextField("添加备注（如：空腹、餐后、用药后等）", text: $note, axis: .vertical)
                .lineLimit(3...5)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
    
    private var saveButton: some View {
        Button {
            saveTapped()
        } label: {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("保存")
                    .fontWeight(.semibold)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    colors: [.blue, .blue.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .disabled(parsedValue == nil || parsedValue ?? 0 <= 0)
        .opacity(parsedValue == nil || parsedValue ?? 0 <= 0 ? 0.6 : 1)
    }

    private var parsedValue: Double? {
        Double(valueText.replacingOccurrences(of: ",", with: "."))
    }
    
    private var userGender: UserGender {
        UserGender(rawValue: userGenderRawValue) ?? .male
    }

    private func saveTapped() {
        guard let value = parsedValue, value > 0 else { return }
        if looksExtreme(value: value, unit: selectedUnit) {
            pendingSaveValue = value
            showingExtremeConfirm = true
            return
        }
        save(value: value)
    }

    private func looksExtreme(value: Double, unit: UricUnit) -> Bool {
        let umolValue = UricUnit.convert(value: value, from: unit, to: .umolL)
        return umolValue < 50 || umolValue > 1200
    }
    
    private func formatValue(_ value: Double) -> String {
        let converted = UricUnit.convert(value: value, from: .umolL, to: selectedUnit)
        if selectedUnit == .umolL {
            return String(format: "%.0f", converted)
        } else {
            return String(format: "%.1f", converted)
        }
    }

    private func save(value: Double) {
        if let record {
            record.measuredAt = measuredAt
            record.value = value
            record.unit = selectedUnit
            record.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            record.updatedAt = Date()
        } else {
            _ = UricAcidRecordEntity.create(
                in: viewContext,
                measuredAt: measuredAt,
                value: value,
                unit: selectedUnit,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        try? viewContext.save()
        dismiss()
    }
}

// MARK: - 参考信息详情页
struct ReferenceInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 单位换算说明
                    unitConversionSection
                    
                    // 正常范围
                    normalRangeSection
                    
                    // 诊断标准
                    diagnosisSection
                    
                    // 痛风控制目标
                    goutControlSection
                    
                    // 注意事项
                    noticeSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("尿酸参考值说明")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
    
    private var unitConversionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "ruler.fill")
                    .foregroundStyle(.blue)
                Text("单位换算")
                    .font(.headline)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("1 mg/dL ≈ 59.48 μmol/L")
                    .font(.system(size: 16, weight: .medium))
                Text("常用单位：μmol/L（也常用 mg/dL）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }
    
    private var normalRangeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(.green)
                Text("血尿酸正常范围（空腹、成人）")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 12) {
                normalRangeRow(
                    title: "成年男性",
                    range: "210～420 μmol/L",
                    subRange: "(3.5～7.0 mg/dL)"
                )
                
                normalRangeRow(
                    title: "成年女性（绝经前）",
                    range: "150～360 μmol/L",
                    subRange: "(2.5～6.0 mg/dL)"
                )
                
                normalRangeRow(
                    title: "绝经后女性",
                    range: "接近男性标准",
                    subRange: "上限约 420 μmol/L"
                )
            }
        }
    }
    
    private func normalRangeRow(title: String, range: String, subRange: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                Text(subRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(range)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
    
    private var diagnosisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "stethoscope")
                    .foregroundStyle(.orange)
                Text("高尿酸血症诊断标准")
                    .font(.headline)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("不分男女")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text("非同日 2 次空腹血尿酸 ＞ 420 μmol/L（7.0 mg/dL），即可诊断。")
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.08))
            )
        }
    }
    
    private var goutControlSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "target")
                    .foregroundStyle(.purple)
                Text("痛风控制目标")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 12) {
                goutControlRow(
                    title: "一般痛风患者",
                    target: "＜ 360 μmol/L",
                    color: .blue
                )
                
                goutControlRow(
                    title: "有痛风石或频繁发作",
                    target: "＜ 300 μmol/L",
                    color: .purple
                )
            }
        }
    }
    
    private func goutControlRow(title: String, target: String, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15))
            
            Spacer()
            
            Text(target)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
    
    private var noticeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("注意事项")
                    .font(.headline)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• 以上参考值适用于空腹、成人血尿酸检测")
                    .font(.caption)
                Text("• 不同医院、不同检测方法可能略有差异")
                    .font(.caption)
                Text("• 请以您就诊医院的参考范围为准")
                    .font(.caption)
                Text("• 如有异常请咨询医生，不要自行诊断")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }
}
