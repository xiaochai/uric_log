import Foundation

struct CSVImportRecord: Sendable {
	let id: UUID
	let measuredAt: Date
	let value: Double
	let unit: UricUnit
	let note: String?
	let createdAt: Date
	let updatedAt: Date
}

/// Only the validator can construct a document ready to be saved.
struct CSVImportDocument: Sendable {
	let records: [CSVImportRecord]
	fileprivate init(records: [CSVImportRecord]) {
		self.records = records
	}
}

enum CSVImporter {
	static let header = ["id", "measured_at", "value", "unit", "note", "created_at", "updated_at"]

	enum ImportError: LocalizedError {
		case invalidEncoding
		case invalidHeader
		case emptyFile
		case malformedCSV(line: Int)
		case invalidField(column: String, line: Int)
		case duplicateID(line: Int)
		case invalidDateOrder(line: Int)

		var errorDescription: String? {
			switch self {
			case .invalidEncoding:
				return L10n.string("IMPORT_INVALID_ENCODING")
			case .invalidHeader:
				return L10n.string("IMPORT_INVALID_HEADER")
			case .emptyFile:
				return L10n.string("IMPORT_EMPTY_FILE")
			case .malformedCSV(let line):
				return L10n.format("IMPORT_MALFORMED_CSV", line)
			case .invalidField(let column, let line):
				return L10n.format("IMPORT_INVALID_FIELD", column, line)
			case .duplicateID(let line):
				return L10n.format("IMPORT_DUPLICATE_ID", line)
			case .invalidDateOrder(let line):
				return L10n.format("IMPORT_INVALID_DATE_ORDER", line)
			}
		}
	}

	static func parse(data: Data) throws -> CSVImportDocument {
		guard var text = String(data: data, encoding: .utf8) else {
			throw ImportError.invalidEncoding
		}
		if text.first == "\u{FEFF}" { text.removeFirst() }
		let rows = try parseRows(text)
		guard let first = rows.first else { throw ImportError.emptyFile }
		guard first.fields == header else { throw ImportError.invalidHeader }
		guard rows.count > 1 else { throw ImportError.emptyFile }

		var identifiers = Set<UUID>()
		var records: [CSVImportRecord] = []
		records.reserveCapacity(rows.count - 1)
		for row in rows.dropFirst() {
			guard row.fields.count == header.count else {
				throw ImportError.malformedCSV(line: row.line)
			}
			let fields = row.fields
			guard matches(uuidPattern, fields[0]), let id = UUID(uuidString: fields[0]) else {
				throw ImportError.invalidField(column: header[0], line: row.line)
			}
			guard identifiers.insert(id).inserted else { throw ImportError.duplicateID(line: row.line) }
			guard let measuredAt = parseDate(fields[1]) else {
				throw ImportError.invalidField(column: header[1], line: row.line)
			}
			guard matches(numberPattern, fields[2]), let value = Double(fields[2]), value.isFinite, value > 0 else {
				throw ImportError.invalidField(column: header[2], line: row.line)
			}
			let unit: UricUnit
			switch fields[3] {
			case "mg/dL": unit = .mgdL
			case "μmol/L", "µmol/L": unit = .umolL
			default: throw ImportError.invalidField(column: header[3], line: row.line)
			}
			guard let createdAt = parseDate(fields[5]) else {
				throw ImportError.invalidField(column: header[5], line: row.line)
			}
			guard let updatedAt = parseDate(fields[6]) else {
				throw ImportError.invalidField(column: header[6], line: row.line)
			}
			guard updatedAt >= createdAt else { throw ImportError.invalidDateOrder(line: row.line) }
			records.append(CSVImportRecord(
				id: id, measuredAt: measuredAt, value: value, unit: unit,
				note: fields[4].isEmpty ? nil : fields[4], createdAt: createdAt, updatedAt: updatedAt
			))
		}
		return CSVImportDocument(records: records)
	}

	private struct Row {
		let fields: [String]
		let line: Int
	}

	private enum FieldState {
		case start, unquoted, quoted, afterQuote
	}

	/// Parse quoted CSV before validating columns, preserving note text verbatim.
	private static func parseRows(_ text: String) throws -> [Row] {
		let bytes = Array(text.utf8)
		var rows: [Row] = []
		var fields: [String] = []
		var field: [UInt8] = []
		var state: FieldState = .start
		var line = 1
		var rowLine = 1
		var rowStarted = false
		var index = 0

		func appendField() {
			fields.append(String(decoding: field, as: UTF8.self))
			field.removeAll(keepingCapacity: true)
		}
		while index < bytes.count {
			let byte = bytes[index]
			guard byte != 0 else { throw ImportError.malformedCSV(line: line) }
			if byte == 13 || byte == 10 {
				let isCRLF = byte == 13 && index + 1 < bytes.count && bytes[index + 1] == 10
				if state == .quoted {
					field.append(byte)
					if isCRLF { field.append(10) }
				} else {
					guard byte != 13 || isCRLF else { throw ImportError.malformedCSV(line: line) }
					appendField()
					rows.append(Row(fields: fields, line: rowLine))
					fields.removeAll(keepingCapacity: true)
					state = .start
					rowStarted = false
				}
				line += 1
				if state != .quoted { rowLine = line }
				index += isCRLF ? 2 : 1
				continue
			}
			rowStarted = true
			switch (state, byte) {
			case (.start, 34):
				state = .quoted
			case (.quoted, 34):
				state = .afterQuote
			case (.afterQuote, 34):
				field.append(34)
				state = .quoted
			case (.unquoted, 34):
				throw ImportError.malformedCSV(line: line)
			case (.quoted, _):
				field.append(byte)
			case (_, 44):
				appendField()
				state = .start
			case (.afterQuote, _):
				throw ImportError.malformedCSV(line: line)
			default:
				field.append(byte)
				state = .unquoted
			}
			index += 1
		}
		guard state != .quoted else { throw ImportError.malformedCSV(line: rowLine) }
		if rowStarted {
			appendField()
			rows.append(Row(fields: fields, line: rowLine))
		}
		return rows
	}

	private static let uuidPattern = try! NSRegularExpression(
		pattern: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
	)
	private static let numberPattern = try! NSRegularExpression(
		pattern: "[+]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?"
	)
	private static let datePattern = try! NSRegularExpression(
		pattern: "([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\\.([0-9]{1,9}))?(Z|[+-][0-9]{2}:[0-9]{2})"
	)

	private static func matches(_ expression: NSRegularExpression, _ text: String) -> Bool {
		let range = NSRange(text.startIndex..., in: text)
		return expression.firstMatch(in: text, range: range)?.range == range
	}

	/// Calendar round-tripping prevents Foundation from normalizing invalid dates.
	private static func parseDate(_ text: String) -> Date? {
		let range = NSRange(text.startIndex..., in: text)
		guard let match = datePattern.firstMatch(in: text, range: range), match.range == range else { return nil }
		func group(_ index: Int) -> String? {
			guard let range = Range(match.range(at: index), in: text) else { return nil }
			return String(text[range])
		}
		guard let year = group(1).flatMap(Int.init), (1...9999).contains(year),
			let month = group(2).flatMap(Int.init), (1...12).contains(month),
			let day = group(3).flatMap(Int.init), (1...31).contains(day),
			let hour = group(4).flatMap(Int.init), (0...23).contains(hour),
			let minute = group(5).flatMap(Int.init), (0...59).contains(minute),
			let second = group(6).flatMap(Int.init), (0...59).contains(second),
			let zone = group(8) else { return nil }
		let offset: Int
		if zone == "Z" {
			offset = 0
		} else {
			let pieces = zone.dropFirst().split(separator: ":")
			guard let zoneHour = Int(pieces[0]), zoneHour <= 23,
				let zoneMinute = Int(pieces[1]), zoneMinute <= 59 else { return nil }
			offset = (zoneHour * 3600 + zoneMinute * 60) * (zone.first == "-" ? -1 : 1)
		}
		guard let timeZone = TimeZone(secondsFromGMT: offset) else { return nil }
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = timeZone
		let components = DateComponents(
			timeZone: timeZone, year: year, month: month, day: day,
			hour: hour, minute: minute, second: second
		)
		guard let date = calendar.date(from: components) else { return nil }
		let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
		guard actual.year == year, actual.month == month, actual.day == day,
			actual.hour == hour, actual.minute == minute, actual.second == second else { return nil }
		let fraction = group(7).flatMap { Double("0." + $0) } ?? 0
		return date.addingTimeInterval(fraction)
	}
}
