import AppKit

struct Shot {
	let input: String
	let output: String
	let eyebrow: String
	let title: String
	let subtitle: String
	let language: String
}

let root = CommandLine.arguments[1]
let outputRoot = CommandLine.arguments[2]

let shots = [
	Shot(input: "en-US/01-records.png", output: "en-US/01-records.png", eyebrow: "URIC ACID LOG", title: "Every Reading,\nClearly Organized", subtitle: "Keep your history easy to scan and understand.", language: "en"),
	Shot(input: "en-US/02-trends.png", output: "en-US/02-trends.png", eyebrow: "PROGRESS AT A GLANCE", title: "See Your Trends\nat a Glance", subtitle: "Follow changes over time with clear charts and statistics.", language: "en"),
	Shot(input: "en-US/03-add-record.png", output: "en-US/03-add-record.png", eyebrow: "FAST AND FOCUSED", title: "Log a Reading\nin Seconds", subtitle: "Record values, measurement time, and helpful notes.", language: "en"),
	Shot(input: "en-US/04-date-time.png", output: "en-US/04-date-time.png", eyebrow: "FLEXIBLE HISTORY", title: "Choose Past Dates\nwith Ease", subtitle: "A quick calendar and time picker keeps entry effortless.", language: "en"),
	Shot(input: "zh-Hans/01-records.png", output: "zh-Hans/01-records.png", eyebrow: "尿酸记录", title: "清晰记录\n每一次变化", subtitle: "历史数据整齐呈现，随时查看更轻松。", language: "zh"),
	Shot(input: "zh-Hans/02-trends.png", output: "zh-Hans/02-trends.png", eyebrow: "趋势分析", title: "变化趋势\n一目了然", subtitle: "通过图表与统计，直观了解近期变化。", language: "zh"),
	Shot(input: "zh-Hans/03-add-record.png", output: "zh-Hans/03-add-record.png", eyebrow: "轻松记录", title: "几秒完成\n一次记录", subtitle: "数值、测量时间和备注，简单清晰。", language: "zh"),
	Shot(input: "zh-Hans/04-date-time.png", output: "zh-Hans/04-date-time.png", eyebrow: "灵活补录", title: "历史日期\n也能快速选择", subtitle: "日历与时间集中选择，补录更方便。", language: "zh")
]

// AppKit renders this 2x, producing App Store's accepted 1284 x 2778 size.
let canvasSize = NSSize(width: 642, height: 1389)
let screenshotWidth: CGFloat = 510
let screenshotY: CGFloat = 14
let screenshotCornerRadius: CGFloat = 29

func font(size: CGFloat, weight: NSFont.Weight, language: String) -> NSFont {
	if language == "zh", let result = NSFont(name: "PingFangSC-Semibold", size: size) {
		return result
	}
	return NSFont.systemFont(ofSize: size, weight: weight)
}

func drawText(_ value: String, rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left, lineSpacing: CGFloat = 0) {
	let paragraph = NSMutableParagraphStyle()
	paragraph.alignment = alignment
	paragraph.lineSpacing = lineSpacing
	value.draw(in: rect, withAttributes: [
		.font: font,
		.foregroundColor: color,
		.paragraphStyle: paragraph
	])
}

for shot in shots {
	guard let source = NSImage(contentsOfFile: root + "/" + shot.input) else {
		fatalError("Unable to load \(shot.input)")
	}

	let canvas = NSImage(size: canvasSize)
	canvas.lockFocus()
	NSColor(calibratedRed: 0.965, green: 0.975, blue: 0.992, alpha: 1).setFill()
	NSRect(origin: .zero, size: canvasSize).fill()

	NSColor(calibratedRed: 0.04, green: 0.53, blue: 0.96, alpha: 1).setFill()
	NSRect(x: 48, y: 1358, width: 36, height: 4).fill()

	drawText(shot.eyebrow, rect: NSRect(x: 48, y: 1314, width: 564, height: 30), font: font(size: 16, weight: .bold, language: shot.language), color: NSColor(calibratedRed: 0.04, green: 0.45, blue: 0.88, alpha: 1))
	drawText(shot.title, rect: NSRect(x: 48, y: 1175, width: 564, height: 125), font: font(size: shot.language == "zh" ? 43 : 39, weight: .bold, language: shot.language), color: NSColor(calibratedWhite: 0.08, alpha: 1), lineSpacing: 2.5)
	drawText(shot.subtitle, rect: NSRect(x: 48, y: 1128, width: 564, height: 38), font: font(size: shot.language == "zh" ? 17.5 : 15.5, weight: .regular, language: shot.language), color: NSColor(calibratedWhite: 0.38, alpha: 1))

	let ratio = source.size.height / source.size.width
	let imageRect = NSRect(x: (canvasSize.width - screenshotWidth) / 2, y: screenshotY, width: screenshotWidth, height: screenshotWidth * ratio)
	NSGraphicsContext.saveGraphicsState()
	let shadow = NSShadow()
	shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
	shadow.shadowBlurRadius = 17
	shadow.shadowOffset = NSSize(width: 0, height: -5)
	shadow.set()
	let path = NSBezierPath(roundedRect: imageRect, xRadius: screenshotCornerRadius, yRadius: screenshotCornerRadius)
	NSColor.white.setFill()
	path.fill()
	path.addClip()
	source.draw(in: imageRect, from: NSRect(origin: .zero, size: source.size), operation: .sourceOver, fraction: 1)
	NSGraphicsContext.restoreGraphicsState()

	canvas.unlockFocus()
	guard let tiff = canvas.tiffRepresentation,
		let bitmap = NSBitmapImageRep(data: tiff),
		let png = bitmap.representation(using: .png, properties: [:]) else {
		fatalError("Unable to encode \(shot.output)")
	}
	let output = URL(fileURLWithPath: outputRoot + "/" + shot.output)
	try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
	try png.write(to: output)
}
