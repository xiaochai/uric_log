import SwiftUI
import CoreData
import Charts

struct TrendsView: View {
	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(keyPath: \UricAcidRecordEntity.measuredAt, ascending: true)]
	) private var records: FetchedResults<UricAcidRecordEntity>

	@AppStorage(AppSettingsKey.preferredUnit) private var preferredUnitRawValue = UricUnit.umolL.rawValue
	@AppStorage(AppSettingsKey.targetEnabled) private var targetEnabled = false
	@AppStorage(AppSettingsKey.targetValue) private var targetValue: Double = 420
	@AppStorage(AppSettingsKey.userGender) private var userGenderRawValue = UserGender.male.rawValue
	@AppStorage(AppSettingsKey.selectedTimeRange) private var timeRangeRawValue = TimeRange.days30.rawValue

	init() {}

	var body: some View {
		ScrollView {
			VStack(spacing: 20) {
				// Time range selector
				timeRangeCard
				
				// Trend chart
				trendChartCard
				
				// Statistics card
				statsCard
			}
			.padding()
		}
		.background(Color(.systemGroupedBackground))
			.navigationTitle("TAB_TRENDS")
			.onChange(of: timeRange) { _, newValue in
				Analytics.track("trends_range_changed", properties: ["range": newValue.rawValue])
			}
		}
	
	// MARK: - Time range card
	private var timeRangeCard: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Image(systemName: "calendar")
					.foregroundStyle(.blue)
				Text("TIME_RANGE")
					.font(.system(size: 17, weight: .semibold))
				Spacer()
			}
			
			Picker("RANGE", selection: timeRangeSelection) {
				ForEach(TimeRange.allCases) { range in
					Text(range.displayName).tag(range)
				}
			}
			.pickerStyle(.segmented)
		}
		.padding()
		.frame(minHeight: 108)
		.background(
			RoundedRectangle(cornerRadius: 16)
				.fill(Color(.secondarySystemGroupedBackground))
		)
		.shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
	}
	
	// MARK: - Trend chart card
	private var trendChartCard: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Image(systemName: "chart.line.uptrend.xyaxis")
					.foregroundStyle(.green)
				Text("URIC_ACID_TREND")
					.font(.system(size: 17, weight: .semibold))
				Spacer()
				
				if targetEnabled {
					targetChip
				}
				
				if !filteredPoints.isEmpty {
					Text(L10n.format("RECORD_COUNT", filteredPoints.count))
						.font(.caption)
						.foregroundStyle(.secondary)
						.padding(.horizontal, 8)
						.padding(.vertical, 4)
						.background(
							Capsule()
								.fill(Color.blue.opacity(0.1))
						)
				}
			}
			
			if filteredPoints.isEmpty {
				emptyChartView
			} else {
				chartView
			}
		}
		.padding()
		.background(
			RoundedRectangle(cornerRadius: 16)
				.fill(Color(.secondarySystemGroupedBackground))
		)
		.shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
	}

	private var targetChip: some View {
		HStack(spacing: 4) {
			Image(systemName: "target")
				.font(.caption2)
			Text(L10n.format("TARGET_VALUE_LABEL", formatValue(targetValue)))
				.font(.caption)
				.lineLimit(1)
				.minimumScaleFactor(0.6)
				.truncationMode(.tail)
		}
		.foregroundStyle(.orange)
		.padding(.horizontal, 8)
		.padding(.vertical, 4)
		.background(
			Capsule()
				.fill(Color.orange.opacity(0.1))
		)
		.frame(maxWidth: 140, alignment: .trailing)
	}
	
	private var emptyChartView: some View {
		VStack(spacing: 12) {
			Image(systemName: "chart.xyaxis.line")
				.font(.system(size: 48))
				.foregroundStyle(.secondary.opacity(0.5))
			Text("TRENDS_EMPTY_TITLE")
				.font(.system(size: 16))
				.foregroundStyle(.secondary)
			Text("TRENDS_EMPTY_MESSAGE")
				.font(.caption)
				.foregroundStyle(.secondary.opacity(0.7))
		}
		.frame(maxWidth: .infinity, minHeight: 200)
		.background(
			RoundedRectangle(cornerRadius: 12)
				.fill(Color(.tertiarySystemFill))
		)
	}
	
	private var chartView: some View {
		VStack(alignment: .trailing, spacing: 4) {
			Text(preferredUnit.displayName)
				.font(.caption2.weight(.medium))
				.foregroundStyle(.secondary)
				.accessibilityLabel(L10n.format("CHART_Y_AXIS_UNIT", preferredUnit.displayName))

			Chart {
			// Show a single reading as a point; connect multiple readings with a smooth curve that avoids overshoot.
			if filteredPoints.count > 1 {
				ForEach(filteredPoints, id: \.recordID) { point in
					LineMark(
						x: .value(L10n.string("TIME"), point.measuredAt),
						y: .value(L10n.string("URIC_ACID"), point.value)
					)
					.interpolationMethod(lineInterpolation)
					.foregroundStyle(
						LinearGradient(
							colors: [.blue, .cyan],
							startPoint: .leading,
							endPoint: .trailing
						)
					)
					.lineStyle(StrokeStyle(lineWidth: 3))
				}
			}

			// Data points
			ForEach(filteredPoints, id: \.recordID) { point in
				PointMark(
					x: .value(L10n.string("TIME"), point.measuredAt),
					y: .value(L10n.string("URIC_ACID"), point.value)
				)
				.symbol {
					Circle()
						.fill(Color.white)
						.frame(width: 10, height: 10)
						.overlay(
							Circle()
								.stroke(point.valueColor, lineWidth: 2)
						)
				}
			}

			if targetEnabled {
				RuleMark(y: .value(L10n.string("TARGET"), targetValue))
					.lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
					.foregroundStyle(
						LinearGradient(
							colors: [.orange, .red],
							startPoint: .leading,
							endPoint: .trailing
						)
					)
			}
			}
			.chartXScale(
				range: .plotDimension(startPadding: 34, endPadding: 34)
			)
			.chartYScale(domain: yDomain)
			.chartPlotStyle { plotArea in
				plotArea
					.clipShape(RoundedRectangle(cornerRadius: 8))
			}
			.chartXAxis {
				AxisMarks(values: xAxisDates) { value in
					AxisGridLine()
						.foregroundStyle(.secondary.opacity(0.2))
					AxisValueLabel {
						if let date = value.as(Date.self) {
							if spansMultipleYears {
								VStack(spacing: 1) {
									Text(date.chineseShortDate)
										.font(.caption2)
									Text(date.localizedYear)
										.font(.caption2.weight(.medium))
										.foregroundStyle(.tertiary)
								}
								.multilineTextAlignment(.center)
							} else {
								Text(date.chineseShortDate)
									.font(.caption)
							}
						}
					}
				}
			}
			.chartYAxis {
				AxisMarks { value in
					AxisGridLine()
						.foregroundStyle(.secondary.opacity(0.2))
					AxisValueLabel {
						if let val = value.as(Double.self) {
							Text(axisValue(val))
								.font(.caption)
								.foregroundStyle(.secondary)
						}
					}
				}
			}
			.frame(height: 260)
		}
		.padding(.vertical, 8)
	}

	private func axisValue(_ value: Double) -> String {
		value.formatted(.number.locale(AppLanguage.selected.locale).precision(.fractionLength(2)))
	}
	
	// MARK: - Statistics card
	private var statsCard: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Image(systemName: "chart.bar.fill")
					.foregroundStyle(.purple)
				Text("STATISTICS")
					.font(.system(size: 17, weight: .semibold))
				Spacer()
			}
			
			LazyVGrid(columns: [
				GridItem(.flexible()),
				GridItem(.flexible())
			], spacing: 12) {
				StatItemView(
					title: "STAT_AVERAGE",
					value: formatValue(stats.average),
					icon: "minus",
					color: .blue
				)
				StatItemView(
					title: "STAT_MINIMUM",
					value: formatValue(stats.min),
					icon: "arrow.down",
					color: .green
				)
				StatItemView(
					title: "STAT_MAXIMUM",
					value: formatValue(stats.max),
					icon: "arrow.up",
					color: .orange
				)
				StatItemView(
					title: "STAT_LATEST",
					value: formatValue(stats.latest),
					icon: "clock",
					color: .purple
				)
			}
			
			if targetEnabled {
				Divider()
					.padding(.vertical, 4)
				
				HStack(spacing: 16) {
					TargetStatView(
						title: "STAT_TARGET_RATE",
						value: String(format: "%.0f%%", stats.targetRate * 100),
						icon: "checkmark.circle.fill",
						color: stats.targetRate >= 0.8 ? .green : .orange
					)
					
					TargetStatView(
						title: "STAT_TARGET_DIFFERENCE",
						value: formatDelta(stats.latest - targetValue),
						icon: (stats.latest - targetValue) <= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill",
						color: (stats.latest - targetValue) <= 0 ? .green : .red
					)
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

	private var filteredPoints: [TrendPoint] {
		let source = Array(records)
		let filtered: [UricAcidRecordEntity]
		if let start = timeRange.startDate() {
			filtered = source.filter { $0.measuredAt >= start }
		} else {
			filtered = source
		}
		return filtered.map { record in
			let convertedValue = UricUnit.convertWithoutRounding(value: record.value, from: record.unit, to: preferredUnit)
			return TrendPoint(
				recordID: record.id,
				measuredAt: record.measuredAt,
				value: convertedValue,
				valueInMicromoles: UricUnit.convertWithoutRounding(value: record.value, from: record.unit, to: .umolL),
				normalUpperUmol: userGender.normalRangeUpper
			)
		}
	}

	private var yDomain: ClosedRange<Double> {
		TrendYAxis.domain(
			values: filteredPoints.map(\.value),
			target: targetEnabled ? targetValue : nil,
			unit: preferredUnit
		)
	}

	/// Snap x-axis ticks to actual record dates. When the data spans multiple years,
	/// use three ticks to avoid crowded labels.
	private var xAxisDates: [Date] {
		let dates = filteredPoints.map(\.measuredAt)
		let desiredCount = spansMultipleYears ? 3 : 4
		guard let first = dates.first,
			let last = dates.last else { return [] }

		let candidates: [Date]
		if dates.count <= desiredCount {
			candidates = dates
		} else {
			let span = last.timeIntervalSince(first)
			let targets = (0..<desiredCount).map { position in
				first.addingTimeInterval(span * Double(position) / Double(desiredCount - 1))
			}
			var selected: [Date] = []
			for target in targets {
				guard let nearest = dates.min(by: {
					abs($0.timeIntervalSince(target)) < abs($1.timeIntervalSince(target))
				}) else { continue }
				if !selected.contains(nearest) { selected.append(nearest) }
			}
			candidates = selected.sorted()
		}

		return removingCrowdedAxisDates(
			from: candidates,
			first: first,
			last: last
		)
	}

	/// Keep data points for nearby records, but omit intermediate date labels that could overlap.
	private func removingCrowdedAxisDates(
		from dates: [Date],
		first: Date,
		last: Date
	) -> [Date] {
		let span = last.timeIntervalSince(first)
		guard span > 0 else { return [first] }
		guard dates.count > 2 else {
			let sameDay = Calendar.current.isDate(first, inSameDayAs: last)
			return sameDay ? [first] : dates
		}

		let minimumGap = span * (spansMultipleYears ? 0.24 : 0.2)
		var result = [first]
		for date in dates.dropFirst().dropLast() {
			guard let previous = result.last,
				date.timeIntervalSince(previous) >= minimumGap,
				last.timeIntervalSince(date) >= minimumGap else { continue }
			result.append(date)
		}
		if last != first { result.append(last) }
		return result
	}

	private var spansMultipleYears: Bool {
		guard let first = filteredPoints.first?.measuredAt,
			let last = filteredPoints.last?.measuredAt else { return false }
		let calendar = Calendar.current
		return calendar.component(.year, from: first) != calendar.component(.year, from: last)
	}

	private var lineInterpolation: InterpolationMethod {
		spansMultipleYears ? .linear : .monotone
	}

	private var stats: TrendStats {
		TrendStats.calculate(
			valuesInMicromoles: filteredPoints.map(\.valueInMicromoles),
			targetInMicromoles: targetEnabled
				? UricUnit.convertWithoutRounding(value: targetValue, from: preferredUnit, to: .umolL)
				: nil,
			unit: preferredUnit
		)
	}

	private var userGender: UserGender {
		UserGender(rawValue: userGenderRawValue) ?? .male
	}

	private func formatValue(_ value: Double) -> String {
		value.formatted(.number.locale(AppLanguage.selected.locale).precision(.fractionLength(2)))
	}

	private func formatDelta(_ delta: Double) -> String {
		let sign = delta > 0 ? "+" : ""
		return "\(sign)\(delta.formatted(.number.locale(AppLanguage.selected.locale).precision(.fractionLength(2))))"
	}
}

/// Calculate in the canonical unit so changing display units preserves the
/// shape of the chart. A small minimum span prevents a degenerate axis for a
/// single reading or identical readings, without forcing the axis to zero.
enum TrendYAxis {
	static func domain(values: [Double], target: Double?, unit: UricUnit) -> ClosedRange<Double> {
		var canonicalValues = values.filter(\.isFinite).map {
			UricUnit.convert(value: $0, from: unit, to: .umolL)
		}
		if let target, target.isFinite {
			canonicalValues.append(UricUnit.convert(value: target, from: unit, to: .umolL))
		}
		guard let minimum = canonicalValues.min(), let maximum = canonicalValues.max() else {
			return convert(0...1, to: unit)
		}
		let span = maximum - minimum
		let minimumSpan = 10.0 // μmol/L, approximately 0.168 mg/dL
		let padding = max(span * 0.15, minimumSpan * 0.15)
		let midpoint = minimum + span / 2
		let halfSpan = max(span, minimumSpan) / 2
		let lower = max(0, midpoint - halfSpan - padding)
		let upper = max(lower + minimumSpan, midpoint + halfSpan + padding)
		return convert(lower...upper, to: unit)
	}

	private static func convert(_ range: ClosedRange<Double>, to unit: UricUnit) -> ClosedRange<Double> {
		let lower = UricUnit.convert(value: range.lowerBound, from: .umolL, to: unit)
		let upper = UricUnit.convert(value: range.upperBound, from: .umolL, to: unit)
		return lower...upper
	}
}

// MARK: - Statistics item view
private struct StatItemView: View {
	let title: String
	let value: String
	let icon: String
	let color: Color
	
	var body: some View {
		VStack(spacing: 8) {
			HStack(spacing: 4) {
				Image(systemName: icon)
					.font(.caption)
					.foregroundStyle(color)
				Text(LocalizedStringKey(title))
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			
			Text(value)
				.font(.system(size: 24, weight: .bold))
				.foregroundStyle(color)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 12)
		.background(
			RoundedRectangle(cornerRadius: 12)
				.fill(color.opacity(0.08))
		)
	}
}

// MARK: - Target statistics view
private struct TargetStatView: View {
	let title: String
	let value: String
	let icon: String
	let color: Color
	
	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: icon)
				.font(.title3)
				.foregroundStyle(color)
			
			VStack(alignment: .leading, spacing: 2) {
				Text(LocalizedStringKey(title))
					.font(.caption)
					.foregroundStyle(.secondary)
				Text(value)
					.font(.system(size: 18, weight: .semibold))
					.foregroundStyle(color)
			}
			
			Spacer()
		}
		.padding()
		.background(
			RoundedRectangle(cornerRadius: 12)
				.fill(color.opacity(0.08))
		)
	}
}

private struct TrendPoint {
	let recordID: UUID
	let measuredAt: Date
	let value: Double
	let valueInMicromoles: Double
	let normalUpperUmol: Double
	
	var valueColor: Color {
		let umolValue = valueInMicromoles
		if UricUnit.isAtOrBelow(umolValue, upperBound: normalUpperUmol) {
			return .green
		}
		let delta = umolValue - normalUpperUmol
		let maxDelta = 200.0
		let ratio = min(max(delta / maxDelta, 0), 1)
		let hue = 0.14 - (0.14 * ratio)
		return Color(hue: hue, saturation: 0.95, brightness: 0.95)
	}
}

private struct TrendStats {
	let average: Double
	let min: Double
	let max: Double
	let latest: Double
	let targetRate: Double

	/// Calculate from original values; round only when formatting for display.
	static func calculate(valuesInMicromoles: [Double], targetInMicromoles: Double?, unit: UricUnit) -> TrendStats {
		let values = valuesInMicromoles.filter(\.isFinite)
		let average = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
		let targetRate: Double
		if let targetInMicromoles, targetInMicromoles.isFinite, !values.isEmpty {
			targetRate = Double(values.filter { UricUnit.isAtOrBelow($0, upperBound: targetInMicromoles) }.count) / Double(values.count)
		} else {
			targetRate = 0
		}
		return TrendStats(
			average: UricUnit.convertWithoutRounding(value: average, from: .umolL, to: unit),
			min: UricUnit.convertWithoutRounding(value: values.min() ?? 0, from: .umolL, to: unit),
			max: UricUnit.convertWithoutRounding(value: values.max() ?? 0, from: .umolL, to: unit),
			latest: UricUnit.convertWithoutRounding(value: values.last ?? 0, from: .umolL, to: unit),
			targetRate: targetRate
		)
	}
}
