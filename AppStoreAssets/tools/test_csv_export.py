"""Exercise the actual CSV exporter and parse its files with Python's CSV reader."""
import csv
import datetime
import decimal
import io
import json
import math
import os
import pathlib
import re
import struct
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[2]
HEADER = ["id", "measured_at", "value", "unit", "note", "created_at", "updated_at"]
LANGUAGES = ["en-US", "zh-Hans", "de", "es", "fr", "it", "pt-PT"]
NOTES = [
    'Before breakfast, "fasting"',
    "First line\nSecond line",
    "Accento: caffè; 中文; 🧪",
    None,
    "",
    "Windows\r\nline endings",
    " tabs\tand spaces ",
    "zero",
    "=literal note",
    'A comma, a quote ", and a newline\nremain intact',
    "One binary step above 1",
    "One binary step above 392",
    "Small mg/dL value",
    "Small micromolar value",
    "Seventeen significant digits",
    "High-precision micromolar value",
]
# Numeric references are independent of the Swift exporter and its formatter.
INPUT_VALUES = [
    (5.29, "mgdL"), (392.0, "umolL"), (1.125, "mgdL"), (1.225, "mgdL"),
    (1.375, "mgdL"), (2.675, "mgdL"), (5.29123456789, "mgdL"), (0.0, "umolL"),
    (100.23, "umolL"), (392.291234, "umolL"),
    (math.nextafter(1.0, math.inf), "mgdL"),
    (math.nextafter(392.0, math.inf), "umolL"),
    (0.000000000123456789, "mgdL"), (5.29123456789e-12, "umolL"),
    (0.12345678901234566, "mgdL"), (1200.1234567890123, "umolL"),
]
NUMBER = re.compile(r"-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?")


def double_bits(value):
    return struct.unpack(">Q", struct.pack(">d", value))[0]


def assert_full_precision(text, expected_bits, original_value, original_unit, output_unit):
    assert NUMBER.fullmatch(text), f"CSV must contain an ungrouped, locale-independent number: {text!r}"
    value = float(text)
    assert math.isfinite(value)
    assert double_bits(value) == int(expected_bits), f"CSV lost Double precision: {text}"
    if original_unit == output_unit:
        assert double_bits(value) == double_bits(original_value), "Same-unit export must preserve the stored value exactly"
    with decimal.localcontext() as context:
        context.prec = 80
        expected = decimal.Decimal.from_float(original_value)
        if original_unit != output_unit:
            if original_unit == "mgdL":
                expected = expected * decimal.Decimal(10000) / decimal.Decimal("168.1103")
            else:
                expected = expected * decimal.Decimal("168.1103") / decimal.Decimal(10000)
        # Account only for IEEE-754 arithmetic, never decimal-place rounding.
        tolerance = decimal.Decimal.from_float(math.ulp(float(expected))) * 4
        assert abs(decimal.Decimal.from_float(value) - expected) <= tolerance, (text, expected)
    return value


def iso_date(seconds):
    return datetime.datetime.fromtimestamp(seconds, datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


units = (ROOT / "UricLog/Models/Unit.swift").read_text()
exporter = (ROOT / "UricLog/Utils/CSVExporter.swift").read_text()
settings = (ROOT / "UricLog/Views/SettingsView.swift").read_text()
filter_start = settings.index("private func filterRecords(")
filter_end = settings.index("{", filter_start) + 1
filter_depth = 1
while filter_depth:
    if settings[filter_end] == "{":
        filter_depth += 1
    elif settings[filter_end] == "}":
        filter_depth -= 1
    filter_end += 1
record_filter = settings[filter_start:filter_end].replace("private ", "", 1)
source = "import Foundation\n" + units[units.index("enum UricUnit:"):units.index("enum AppSettingsKey")]
source += r'''
struct ActiveLanguage { let locale: Locale }
enum AppLanguage { static var selected = ActiveLanguage(locale: Locale(identifier: "en-US")) }
enum L10n { static func string(_ key: String) -> String { key } }
struct UricAcidRecordEntity {
    let id: UUID
    let measuredAt: Date
    let value: Double
    let unit: UricUnit
    let note: String?
    let createdAt: Date
    let updatedAt: Date
}
'''
source += exporter
source += units[units.index("enum TimeRange:"):]
source += "\nstruct CSVRecordFilter {\n" + record_filter + "\n}\n"
source += r'''
if CommandLine.arguments.contains("--expect-write-failure") {
    do {
        _ = try CSVExporter.export(records: [], preferredUnit: .mgdL)
        fatalError("Export unexpectedly succeeded below a regular file")
    } catch CSVExporter.ExportError.failedToWrite {
        assert(errorDescriptionForTest() == "EXPORT_ERROR")
        print("PASS localized write failure")
    } catch {
        fatalError("Unexpected error: \(error)")
    }
} else {
    let values: [(Double, UricUnit)] = [
        (5.29, .mgdL), (392, .umolL), (1.125, .mgdL), (1.225, .mgdL),
        (1.375, .mgdL), (2.675, .mgdL), (5.29123456789, .mgdL), (0, .umolL),
        (100.23, .umolL), (392.291234, .umolL),
        (Double(1).nextUp, .mgdL), (Double(392).nextUp, .umolL),
        (0.000000000123456789, .mgdL), (5.29123456789e-12, .umolL),
        (0.12345678901234566, .mgdL), (1200.1234567890123, .umolL)
    ]
    let notes: [String?] = [
        "Before breakfast, \"fasting\"", "First line\nSecond line",
        "Accento: caffè; 中文; 🧪", nil, "", "Windows\r\nline endings",
        " tabs\tand spaces ", "zero", "=literal note",
        "A comma, a quote \", and a newline\nremain intact",
        "One binary step above 1", "One binary step above 392",
        "Small mg/dL value", "Small micromolar value",
        "Seventeen significant digits", "High-precision micromolar value"
    ]
    let records = values.enumerated().map { index, measurement in
        UricAcidRecordEntity(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
            measuredAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 60),
            value: measurement.0, unit: measurement.1, note: notes[index],
            createdAt: Date(timeIntervalSince1970: 1_700_100_000 + Double(index)),
            updatedAt: Date(timeIntervalSince1970: 1_700_200_000 + Double(index))
        )
    }
    var exports: [[String: String]] = []
    var convertedBits: [String: [String]] = [:]
    for unit in UricUnit.allCases {
        convertedBits[unit.rawValue] = values.map {
            String(UricUnit.convertWithoutRounding(value: $0.0, from: $0.1, to: unit).bitPattern)
        }
    }
    for language in ["en-US", "zh-Hans", "de", "es", "fr", "it", "pt-PT"] {
        AppLanguage.selected = ActiveLanguage(locale: Locale(identifier: language))
        for unit in UricUnit.allCases {
            let url = try CSVExporter.export(records: Array(records.reversed()), preferredUnit: unit)
            exports.append(["language": language, "unit": unit.rawValue, "path": url.path])
        }
    }
    let empty = try CSVExporter.export(records: [], preferredUnit: .mgdL)
    var rapidPaths: [String] = []
    for _ in 0..<20 {
        rapidPaths.append(try CSVExporter.export(records: records, preferredUnit: .mgdL).path)
    }
    let now = Date()
    let ages = [0, 6, 8, 29, 31, 89, 91, 200]
    let agedRecords = ages.enumerated().map { index, days in
        UricAcidRecordEntity(
            id: UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", index + 1))!,
            measuredAt: Calendar.current.date(byAdding: .day, value: -days, to: now)!,
            value: 300 + Double(index), unit: .umolL, note: "age=\(days)",
            createdAt: now, updatedAt: now
        )
    }
    var ranges: [[String: Any]] = []
    for range in TimeRange.allCases {
        let filtered = CSVRecordFilter().filterRecords(records: agedRecords, range: range)
        let expectedCount: Int
        switch range {
        case .days7: expectedCount = 2
        case .days30: expectedCount = 4
        case .days90: expectedCount = 6
        case .all: expectedCount = 8
        }
        assert(filtered.count == expectedCount, "Unexpected filter count for \(range)")
        let url = try CSVExporter.export(records: filtered, preferredUnit: .mgdL)
        let emptyCandidates: [UricAcidRecordEntity] = range == .all ? [] : [agedRecords.last!]
        let emptyFiltered = CSVRecordFilter().filterRecords(records: emptyCandidates, range: range)
        assert(emptyFiltered.isEmpty)
        let emptyURL = try CSVExporter.export(records: emptyFiltered, preferredUnit: .mgdL)
        let bits = filtered.sorted { $0.measuredAt < $1.measuredAt }.map {
            String(UricUnit.convertWithoutRounding(value: $0.value, from: $0.unit, to: .mgdL).bitPattern)
        }
        ranges.append(["range": range.rawValue, "path": url.path, "empty": emptyURL.path, "bits": bits])
    }
    let manifest: [String: Any] = [
        "exports": exports, "empty": empty.path, "rapid": rapidPaths, "ranges": ranges,
        "convertedBits": convertedBits, "inputBits": values.map { String($0.0.bitPattern) },
        "inputUnits": values.map { $0.1.rawValue }
    ]
    let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}

func errorDescriptionForTest() -> String? {
    CSVExporter.ExportError.failedToWrite.errorDescription
}
'''

with tempfile.TemporaryDirectory(prefix="uric-csv-tests-") as temporary:
    directory = pathlib.Path(temporary)
    swift = directory / "csv-tests.swift"
    executable = directory / "csv-tests"
    swift.write_text(source)
    subprocess.run(
        ["swiftc", "-module-cache-path", str(directory / "module-cache"), str(swift), "-o", str(executable)],
        check=True,
    )
    exports_directory = directory / "exports"
    exports_directory.mkdir()
    environment = dict(os.environ, TMPDIR=str(exports_directory))
    completed = subprocess.run([str(executable)], check=True, capture_output=True, text=True, env=environment)
    manifest = json.loads(completed.stdout)
    assert [int(bits) for bits in manifest["inputBits"]] == [double_bits(value) for value, _ in INPUT_VALUES]
    assert manifest["inputUnits"] == [unit for _, unit in INPUT_VALUES]
    assert len(INPUT_VALUES) == len(NOTES)
    paths = [entry["path"] for entry in manifest["exports"]] + [manifest["empty"]] + manifest["rapid"]
    paths += [entry[key] for entry in manifest["ranges"] for key in ["path", "empty"]]
    assert len(set(paths)) == len(paths), "Consecutive exports must never overwrite one another"
    checked_rows = 0
    for entry in manifest["exports"]:
        path = pathlib.Path(entry["path"])
        assert path.suffix == ".csv" and path.name.startswith("uric_log_")
        text = path.read_bytes().decode("utf-8")
        rows = list(csv.reader(io.StringIO(text, newline="")))
        assert rows[0] == HEADER
        assert len(rows) == len(NOTES) + 1
        for index, row in enumerate(rows[1:]):
            assert len(row) == len(HEADER), (entry, row)
            assert row[0] == f"00000000-0000-0000-0000-{index + 1:012d}"
            assert row[1] == iso_date(1_700_000_000 + index * 60)
            original_value, original_unit = INPUT_VALUES[index]
            assert_full_precision(
                row[2], manifest["convertedBits"][entry["unit"]][index],
                original_value, original_unit, entry["unit"],
            )
            assert row[3] == ("mg/dL" if entry["unit"] == "mgdL" else "μmol/L")
            assert row[4] == (NOTES[index] or ""), (index, repr(row[4]))
            assert row[5] == iso_date(1_700_100_000 + index)
            assert row[6] == iso_date(1_700_200_000 + index)
            checked_rows += 1
        if entry["unit"] == "mgdL":
            assert rows[7][2] == "5.29123456789", "The CSV must keep all stored decimal digits"
            assert float(rows[11][2]) != 1.0, "The last significant binary digit must survive export"
        else:
            assert rows[10][2] == "392.291234", "The CSV must keep all stored decimal digits"
            assert float(rows[12][2]) != 392.0, "The last significant binary digit must survive export"
        print("PASS full-precision CSV round trip, formulas, dates and escaping", entry["language"], entry["unit"])
    assert pathlib.Path(manifest["empty"]).read_text() == ",".join(HEADER) + "\n"
    print(f"PASS {checked_rows} parsed rows, header-only empty export and {len(paths)} unique export files")
    expected_counts = {"days7": 2, "days30": 4, "days90": 6, "all": 8}
    ages = [0, 6, 8, 29, 31, 89, 91, 200]
    for entry in manifest["ranges"]:
        count = expected_counts[entry["range"]]
        text = pathlib.Path(entry["path"]).read_bytes().decode("utf-8")
        rows = list(csv.reader(io.StringIO(text, newline="")))
        assert rows[0] == HEADER and len(rows) == count + 1
        expected_indices = list(reversed(range(count)))
        assert [row[0] for row in rows[1:]] == [f"10000000-0000-0000-0000-{index + 1:012d}" for index in expected_indices]
        assert [row[4] for row in rows[1:]] == [f"age={ages[index]}" for index in expected_indices]
        for position, (row, index) in enumerate(zip(rows[1:], expected_indices)):
            assert row[3] == "mg/dL"
            assert_full_precision(row[2], entry["bits"][position], 300.0 + index, "umolL", "mgdL")
        assert pathlib.Path(entry["empty"]).read_text() == ",".join(HEADER) + "\n"
        print("PASS actual Settings filter and CSV export", entry["range"], count, "rows and empty result")
    blocked_path = directory / "not-a-directory"
    blocked_path.write_text("A file cannot contain export directories")
    failure_environment = dict(os.environ, TMPDIR=str(blocked_path / "child"))
    failed = subprocess.run(
        [str(executable), "--expect-write-failure"],
        check=True, capture_output=True, text=True, env=failure_environment,
    )
    assert "PASS localized write failure" in failed.stdout
    print(failed.stdout.strip())
