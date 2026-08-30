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

	@State private var timeRange: TimeRange = .days30

	init() {}

	var body: some View {
		ScrollView {
			VStack(spacing: 20) {
				// 时间范围选择器
				timeRangeCard
				
				// 趋势图
				trendChartCard
				
				// 统计卡片
				statsCard
			}
			.padding()
		}
		.background(Color(.systemGroupedBackground))
			.navigationTitle("趋势")
			.onChange(of: timeRange) { _, newValue in
				Analytics.track("trends_range_changed", properties: ["range": newValue.rawValue])
			}
		}
	
	// MARK: - 时间范围卡片
	private var timeRangeCard: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Image(systemName: "calendar")
					.foregroundStyle(.blue)
				Text("时间范围")
					.font(.system(size: 17, weight: .semibold))
				Spacer()
			}
			
			Picker("范围", selection: $timeRange) {
				ForEach(TimeRange.allCases) { range in
					Text(range.displayName).tag(range)
				}
			}
			.pickerStyle(.segmented)
		}
		.padding()
		.background(
			RoundedRectangle(cornerRadius: 16)
				.fill(Color(.secondarySystemGroupedBackground))
		)
		.shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
	}
	
	// MARK: - 趋势图卡片
	private var trendChartCard: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Image(systemName: "chart.line.uptrend.xyaxis")
					.foregroundStyle(.green)
				Text("尿酸趋势")
					.font(.system(size: 17, weight: .semibold))
				Spacer()
				
				if targetEnabled {
					targetChip
				}
				
				if !filteredPoints.isEmpty {
					Text("\(filteredPoints.count) 条记录")
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
			Text("目标 \(formatValue(targetValue))")
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
			Text("暂无数据")
				.font(.system(size: 16))
				.foregroundStyle(.secondary)
			Text("添加记录后即可查看趋势图")
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
		Chart {
			// 渐变区域
			ForEach(filteredPoints, id: \.recordID) { point in
				AreaMark(
					x: .value("时间", point.measuredAt),
					y: .value("尿酸", point.value)
				)
				.interpolationMethod(.catmullRom)
				.foregroundStyle(
					LinearGradient(
						colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.05)],
						startPoint: .top,
						endPoint: .bottom
					)
				)
			}
			
			// 线条
			ForEach(filteredPoints, id: \.recordID) { point in
				LineMark(
					x: .value("时间", point.measuredAt),
					y: .value("尿酸", point.value)
				)
				.interpolationMethod(.catmullRom)
				.foregroundStyle(
					LinearGradient(
						colors: [.blue, .cyan],
						startPoint: .leading,
						endPoint: .trailing
					)
				)
				.lineStyle(StrokeStyle(lineWidth: 3))
			}

			// 数据点
			ForEach(filteredPoints, id: \.recordID) { point in
				PointMark(
					x: .value("时间", point.measuredAt),
					y: .value("尿酸", point.value)
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
				RuleMark(y: .value("目标", targetValue))
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
		.chartYScale(domain: yDomain)
		.chartPlotStyle { plotArea in
			plotArea
				.clipShape(RoundedRectangle(cornerRadius: 8))
		}
		.chartXAxis {
			AxisMarks(values: .automatic(desiredCount: 4)) { value in
				AxisGridLine()
					.foregroundStyle(.secondary.opacity(0.2))
				AxisValueLabel {
					if let date = value.as(Date.self) {
						Text(date.chineseShortDate)
							.font(.caption)
							.foregroundStyle(.secondary)
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
						Text("\(Int(val))")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
			}
		}
		.frame(height: 260)
		.padding(.vertical, 8)
	}
	
	// MARK: - 统计卡片
	private var statsCard: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Image(systemName: "chart.bar.fill")
					.foregroundStyle(.purple)
				Text("统计数据")
					.font(.system(size: 17, weight: .semibold))
				Spacer()
			}
			
			LazyVGrid(columns: [
				GridItem(.flexible()),
				GridItem(.flexible())
			], spacing: 12) {
				StatItemView(
					title: "平均值",
					value: formatValue(stats.average),
					icon: "minus",
					color: .blue
				)
				StatItemView(
					title: "最小值",
					value: formatValue(stats.min),
					icon: "arrow.down",
					color: .green
				)
				StatItemView(
					title: "最大值",
					value: formatValue(stats.max),
					icon: "arrow.up",
					color: .orange
				)
				StatItemView(
					title: "最新值",
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
						title: "达标率",
						value: String(format: "%.0f%%", stats.targetRate * 100),
						icon: "checkmark.circle.fill",
						color: stats.targetRate >= 0.8 ? .green : .orange
					)
					
					TargetStatView(
						title: "距目标",
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

	private var filteredPoints: [TrendPoint] {
		let source = Array(records)
		let filtered: [UricAcidRecordEntity]
		if let start = timeRange.startDate() {
			filtered = source.filter { $0.measuredAt >= start }
		} else {
			filtered = source
		}
		return filtered.map { record in
			let convertedValue = UricUnit.convert(value: record.value, from: record.unit, to: preferredUnit)
			return TrendPoint(
				recordID: record.id,
				measuredAt: record.measuredAt,
				value: convertedValue,
				unit: preferredUnit
				,normalUpperUmol: userGender.normalRangeUpper
			)
		}
	}

	private var yDomain: ClosedRange<Double> {
		var values = filteredPoints.map(\.value)
		if targetEnabled {
			values.append(targetValue)
		}
		let minValue = values.min() ?? 0
		let maxValue = values.max() ?? 1
		let padding = max(10, (maxValue - minValue) * 0.15)
		let lower = max(0, minValue - padding)
		let upper = maxValue + padding
		return lower...upper
	}

	private var stats: TrendStats {
		let values = filteredPoints.map(\.value)
		let average = values.isEmpty ? 0 : (values.reduce(0, +) / Double(values.count))
		let minValue = values.min() ?? 0
		let maxValue = values.max() ?? 0
		let latest = values.last ?? 0
		let targetRate: Double
		if targetEnabled, !values.isEmpty {
			targetRate = Double(values.filter { $0 <= targetValue }.count) / Double(values.count)
		} else {
			targetRate = 0
		}
		return TrendStats(average: average, min: minValue, max: maxValue, latest: latest, targetRate: targetRate)
	}

	private var userGender: UserGender {
		UserGender(rawValue: userGenderRawValue) ?? .male
	}

	private func formatValue(_ value: Double) -> String {
		"\(String(format: "%.0f", value))"
	}

	private func formatDelta(_ delta: Double) -> String {
		let sign = delta > 0 ? "+" : ""
		return "\(sign)\(String(format: "%.0f", delta))"
	}
}

// MARK: - 统计项视图
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
				Text(title)
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

// MARK: - 目标统计视图
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
				Text(title)
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
	let unit: UricUnit
	let normalUpperUmol: Double
	
	var valueColor: Color {
		let umolValue = UricUnit.convert(value: value, from: unit, to: .umolL)
		if umolValue <= normalUpperUmol {
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
}
