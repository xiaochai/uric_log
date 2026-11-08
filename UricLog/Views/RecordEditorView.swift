import SwiftUI
import CoreData

struct RecordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
	@FocusState private var focusedField: FocusField?

    @AppStorage(AppSettingsKey.preferredUnit) private var preferredUnitRawValue = UricUnit.umolL.rawValue
    @AppStorage(AppSettingsKey.userGender) private var userGenderRawValue = UserGender.male.rawValue

    private let record: UricAcidRecordEntity?

    @State private var valueText: String = ""
    @State private var selectedUnit: UricUnit = .umolL
    @State private var measuredAt: Date = Date()
    @State private var draftMeasuredAt: Date = Date()
    @State private var note: String = ""
    @State private var showingExtremeConfirm = false
    @State private var showingReferenceInfo = false
	@State private var showingDatePicker = false
    @State private var pendingSaveValue: Double?

	private enum FocusField: Hashable {
		case value
		case note
	}

    init(record: UricAcidRecordEntity?) {
        self.record = record
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Value input card
                valueInputCard
                
                // Reference range card
                referenceRangeCard
                
                // Time selection card
                timeSelectionCard
                
                // Notes card
                noteCard
                
                // Save button
                saveButton
            }
            .padding()
			.contentShape(Rectangle())
			.onTapGesture {
				focusedField = nil
			}
        }
		.scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L10n.string(record == nil ? "ADD_RECORD" : "EDIT_RECORD"))
        .navigationBarTitleDisplayMode(.large)
	        .toolbar {
	            ToolbarItem(placement: .cancellationAction) {
	                Button("CANCEL") {
	                    Analytics.track("record_editor_cancelled", properties: ["mode": editorMode])
	                    dismiss()
	                }
	            }
	        }
	        .alert("UNUSUAL_VALUE_TITLE", isPresented: $showingExtremeConfirm) {
	            Button("CANCEL", role: .cancel) {
	                Analytics.track("extreme_value_save_cancelled", properties: ["mode": editorMode])
	                pendingSaveValue = nil
	            }
	            Button("SAVE_ANYWAY", role: .destructive) {
	                Analytics.track("extreme_value_save_confirmed", properties: ["mode": editorMode])
                if let value = pendingSaveValue {
                    save(value: value)
                }
                pendingSaveValue = nil
            }
        } message: {
            Text("UNUSUAL_VALUE_MESSAGE")
        }
        .sheet(isPresented: $showingReferenceInfo) {
            ReferenceInfoSheet()
        }
		.sheet(isPresented: $showingDatePicker) {
			measurementTimePicker
				.presentationDetents([.medium])
				.presentationDragIndicator(.visible)
		}
        .onAppear {
            selectedUnit = UricUnit(rawValue: preferredUnitRawValue) ?? .umolL
            if let record {
                measuredAt = record.measuredAt
                selectedUnit = record.unit
                valueText = MeasurementValueText.editing(
                    record.value, locale: AppLanguage.selected.locale
                )
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
                
                Text("URIC_ACID_VALUE")
                    .font(.headline)
                
                Spacer()
            }
            
            HStack(spacing: 12) {
                TextField("VALUE_PLACEHOLDER", text: $valueText)
                    .keyboardType(.decimalPad)
					.focused($focusedField, equals: .value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .frame(height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.05))
                    )
                
                VStack(spacing: 8) {
	                    ForEach(UricUnit.allCases) { unit in
	                        Button {
							focusedField = nil
	                            Analytics.track("record_unit_selected", properties: ["unit": unit.rawValue])
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
                
                Text("REFERENCE_RANGE")
                    .font(.headline)
                
                Spacer()
                
	                Button {
	                    Analytics.track("reference_info_opened")
	                    showingReferenceInfo = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
				.accessibilityLabel("SOURCES_AND_REFERENCES")
            }
            
            // Normal range for the selected gender
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.format("PERSONAL_REFERENCE_RANGE", userGender.displayName))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                
                Text(userGender.normalRangeText(unit: selectedUnit))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.cyan)
			Text("SOURCES_HINT")
				.font(.caption)
				.foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.cyan.opacity(0.08))
            )
            
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
            
            Text(LocalizedStringKey(title))
                .font(.system(size: 15, weight: .medium))
            
            Spacer()
            
            Text(LocalizedStringKey(description))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private func goutControlHint(umolValue: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.vertical, 4)
            
            Text("GOUT_CONTROL_TARGETS")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GOUT")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("< \(formatValue(360)) \(selectedUnit.displayName)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(umolValue < 360 ? .green : .secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("TOPHI_OR_FREQUENT_FLARES")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("< \(formatValue(300)) \(selectedUnit.displayName)")
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
                
                Text("MEASUREMENT_TIME")
                    .font(.headline)
                
                Spacer()
            }
            
			Button {
				focusedField = nil
				draftMeasuredAt = measuredAt
				showingDatePicker = true
			} label: {
				HStack(spacing: 12) {
					Text(measuredAt.chineseDateTime)
						.font(.system(size: 17, weight: .medium))
						.foregroundStyle(.primary)
					Spacer()
					Image(systemName: "chevron.right")
						.font(.caption)
						.foregroundStyle(.tertiary)
				}
				.padding(14)
				.background(
					RoundedRectangle(cornerRadius: 10)
						.fill(Color(.systemBackground))
				)
			}
			.buttonStyle(.plain)
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
                
                Text("NOTES")
                    .font(.headline)
                
                Spacer()
                
                Text("OPTIONAL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            TextField("NOTE_PLACEHOLDER", text: $note, axis: .vertical)
				.focused($focusedField, equals: .note)
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

	private var measurementTimePicker: some View {
		NavigationStack {
			VStack(spacing: 18) {
				Text(draftMeasuredAt.chineseDateTime)
					.font(.system(size: 19, weight: .semibold))
					.frame(maxWidth: .infinity)
					.padding(.top, 8)

				HStack(spacing: 10) {
					quickDateButton("TODAY", dayOffset: 0)
					quickDateButton("YESTERDAY", dayOffset: -1)
					Button("NOW") { draftMeasuredAt = Date() }
						.font(.subheadline.weight(.semibold))
						.frame(maxWidth: .infinity)
						.padding(.vertical, 10)
						.background(Color.blue.opacity(0.1))
						.clipShape(RoundedRectangle(cornerRadius: 8))
						.buttonStyle(.plain)
				}

				VStack(spacing: 0) {
					datePickerRow(title: "DATE", components: .date)
					Divider().padding(.leading, 16)
					datePickerRow(title: "TIME", components: .hourAndMinute)
				}
				.background(Color(.secondarySystemGroupedBackground))
				.clipShape(RoundedRectangle(cornerRadius: 12))

				Label("DATE_PICKER_YEAR_HINT", systemImage: "calendar.badge.clock")
					.font(.caption)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
				Spacer(minLength: 0)
			}
			.padding(.horizontal)
			.navigationTitle("SELECT_MEASUREMENT_TIME")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("CANCEL") { showingDatePicker = false }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("DONE") {
						measuredAt = draftMeasuredAt
						showingDatePicker = false
					}
				}
			}
		}
	}

	private func datePickerRow(title: LocalizedStringKey, components: DatePickerComponents) -> some View {
		HStack {
			Text(title)
				.font(.body.weight(.medium))
			Spacer()
			DatePicker("", selection: $draftMeasuredAt, displayedComponents: components)
				.datePickerStyle(.compact)
				.labelsHidden()
		}
		.padding(.horizontal, 16)
		.frame(minHeight: 54)
	}

	private func quickDateButton(_ title: LocalizedStringKey, dayOffset: Int) -> some View {
		Button {
			let calendar = Calendar.current
			guard let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: Date()) else { return }
			let day = calendar.dateComponents([.year, .month, .day], from: targetDay)
			let time = calendar.dateComponents([.hour, .minute], from: draftMeasuredAt)
			var components = DateComponents()
			components.year = day.year
			components.month = day.month
			components.day = day.day
			components.hour = time.hour
			components.minute = time.minute
			if let date = calendar.date(from: components) {
				draftMeasuredAt = date
			}
		} label: {
			Text(title)
				.font(.subheadline.weight(.semibold))
				.frame(maxWidth: .infinity)
				.padding(.vertical, 10)
				.background(Color.blue.opacity(0.1))
				.clipShape(RoundedRectangle(cornerRadius: 8))
		}
		.buttonStyle(.plain)
	}
    
    private var saveButton: some View {
        Button {
            saveTapped()
        } label: {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("SAVE")
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
        MeasurementValueText.valueForSaving(
            valueText, originalValue: record?.value, locale: AppLanguage.selected.locale
        )
    }
    
    private var userGender: UserGender {
        UserGender(rawValue: userGenderRawValue) ?? .male
    }

	    private func saveTapped() {
	        guard let value = parsedValue, value > 0 else { return }
	        Analytics.track("record_save_tapped", properties: ["mode": editorMode])
	        if looksExtreme(value: value, unit: selectedUnit) {
	            Analytics.track("extreme_value_warning_shown", properties: ["mode": editorMode])
            pendingSaveValue = value
            showingExtremeConfirm = true
            return
        }
        save(value: value)
    }

    private func looksExtreme(value: Double, unit: UricUnit) -> Bool {
        let umolValue = UricUnit.convertWithoutRounding(value: value, from: unit, to: .umolL)
        return umolValue < 50 || umolValue > 1200
    }
    
    private func formatValue(_ value: Double) -> String {
        let converted = UricUnit.convertWithoutRounding(value: value, from: .umolL, to: selectedUnit)
        return converted.formatted(
            .number.locale(AppLanguage.selected.locale).precision(.fractionLength(2))
        )
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
	        do {
	            try viewContext.save()
	            Analytics.track("record_saved", properties: ["mode": editorMode])
	            dismiss()
	        } catch {
	            Analytics.track("record_save_failed", properties: ["mode": editorMode])
	        }
	    }

	private var editorMode: String {
		record == nil ? "create" : "edit"
	}
}

/// Display two decimals while preserving the original value on an unchanged edit.
/// Saving a note, date or unit correction must not discard hidden decimal places.
enum MeasurementValueText {
    static func editing(_ value: Double, locale: Locale) -> String {
        value.formatted(
            .number.locale(locale)
                .grouping(.never)
                .precision(.fractionLength(2))
        )
    }

    static func valueForSaving(_ text: String, originalValue: Double?, locale: Locale) -> Double? {
        guard let value = parse(text) else { return nil }
        if let originalValue, text == editing(originalValue, locale: locale) {
            return originalValue
        }
        return value
    }

    static func parse(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }
}

// MARK: - Reference information details
struct ReferenceInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Unit conversion explanation
                    unitConversionSection
                    
                    // Normal range
                    normalRangeSection
                    
                    // Precautions
                    noticeSection
					
					sourcesSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
			.navigationTitle("REFERENCE_INFORMATION")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
	                    Button("DONE") {
	                        Analytics.track("reference_info_closed")
	                        dismiss()
	                    }
                }
            }
        }
    }
    
    private var unitConversionSection: some View {
        let molarMassText = 168.1103.formatted(
            .number.locale(AppLanguage.selected.locale)
                .grouping(.never)
                .precision(.fractionLength(4))
        )
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "ruler.fill")
                    .foregroundStyle(.blue)
                Text("UNIT_CONVERSION")
                    .font(.headline)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "μmol/L = mg/dL × 10000 ÷ \(molarMassText)")
                    .font(.system(size: 16, weight: .medium))
                Text(verbatim: "mg/dL = μmol/L × \(molarMassText) ÷ 10000")
                    .font(.system(size: 16, weight: .medium))
                Text("COMMON_UNITS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
				Text("UNIT_CONVERSION_DESCRIPTION")
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
				Text("ADULT_REFERENCE_RANGES")
                    .font(.headline)
                Spacer()
            }
			
			Text("REFERENCE_RANGE_DISCLAIMER")
				.font(.caption)
				.foregroundStyle(.secondary)
            
			VStack(spacing: 12) {
				normalRangeRow(
					title: "ADULT_MEN",
					gender: .male
				)
				
				normalRangeRow(
					title: "ADULT_WOMEN",
					gender: .female
				)
			}
        }
    }
    
    private func normalRangeRow(title: String, gender: UserGender) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 15, weight: .medium))
                Text("(\(gender.normalRangeText(unit: .mgdL)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(gender.normalRangeText(unit: .umolL))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)
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
                Text("IMPORTANT_NOTES")
                    .font(.headline)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
				Text("DISCLAIMER_PERSONAL_USE")
					.font(.caption)
					.foregroundStyle(.orange)
                Text("DISCLAIMER_FASTING_ADULTS")
                    .font(.caption)
                Text("DISCLAIMER_LAB_VARIATION")
                    .font(.caption)
                Text("DISCLAIMER_LAB_REFERENCE")
                    .font(.caption)
                Text("DISCLAIMER_CONSULT_DOCTOR")
                    .font(.caption)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }
	
	private var sourcesSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Image(systemName: "book.fill")
					.foregroundStyle(.indigo)
				Text("SOURCES_AND_REFERENCES")
					.font(.headline)
				Spacer()
			}
			
			VStack(alignment: .leading, spacing: 10) {
				Link("SOURCE_GOUT_GUIDELINE_2019", destination: URL(string: "https://doi.org/10.1002/acr.24180")!)
					.font(.caption)
					.foregroundStyle(.blue)
				Link("SOURCE_DIETARY_GUIDELINE_2024", destination: URL(string: "https://ard.bmj.com/content/76/1/29")!)
					.font(.caption)
					.foregroundStyle(.blue)
				Link("SOURCE_YOULAI_REFERENCE_RANGES", destination: URL(string: "https://medlineplus.gov/lab-tests/uric-acid-blood-test/")!)
					.font(.caption)
					.foregroundStyle(.blue)
				Link("SOURCE_PUBCHEM_URIC_ACID", destination: URL(string: "https://pubchem.ncbi.nlm.nih.gov/compound/Uric-acid")!)
					.font(.caption)
					.foregroundStyle(.blue)
			}
			.padding()
			.background(
				RoundedRectangle(cornerRadius: 12)
					.fill(Color(.secondarySystemGroupedBackground))
			)
		}
	}
}
