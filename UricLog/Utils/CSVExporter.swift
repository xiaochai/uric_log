import Foundation

enum CSVExporter {
	enum ExportError: LocalizedError {
		case failedToWrite

		var errorDescription: String? {
			switch self {
			case .failedToWrite:
				return L10n.string("导出失败")
			}
		}
	}

	static func export(records: [UricAcidRecordEntity], preferredUnit: UricUnit) throws -> URL {
		let header = "id,measured_at,value,unit,note,created_at,updated_at\n"
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

		var csv = header
		for record in records.sorted(by: { $0.measuredAt < $1.measuredAt }) {
			let convertedValue = UricUnit.convert(value: record.value, from: record.unit, to: preferredUnit)
			let valueString = String(format: "%.2f", convertedValue)
			let note = (record.note ?? "").replacingOccurrences(of: "\"", with: "\"\"")
			let measuredAt = formatter.string(from: record.measuredAt)
			let createdAt = formatter.string(from: record.createdAt)
			let updatedAt = formatter.string(from: record.updatedAt)
			csv += "\(record.id.uuidString),\(measuredAt),\(valueString),\(preferredUnit.displayName),\"\(note)\",\(createdAt),\(updatedAt)\n"
		}

		let fileName = "uric_log_\(Int(Date().timeIntervalSince1970)).csv"
		let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
		guard let data = csv.data(using: .utf8) else {
			throw ExportError.failedToWrite
		}
		do {
			try data.write(to: url, options: .atomic)
			return url
		} catch {
			throw ExportError.failedToWrite
		}
	}
}
