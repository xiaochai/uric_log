"""Validate the actual Swift CSV importer against independent CSV fixtures."""
import base64
import csv
import datetime
import io
import json
import math
import os
import pathlib
import struct
import subprocess
import tempfile
import uuid


ROOT = pathlib.Path(__file__).resolve().parents[2]
HEADER = ["id", "measured_at", "value", "unit", "note", "created_at", "updated_at"]
BASE = [
    "12345678-90AB-CDEF-1234-567890ABCDEF",
    "2026-11-08T08:12:13.123Z",
    "5.29123456789",
    "mg/dL",
    'Caffè, "fasting"\n中文 🧪',
    "2026-11-08T09:00:00.000Z",
    "2026-11-08T09:00:00.001Z",
]
fixtures = []


def encode_csv(rows, header=HEADER, ending="\n", quoted=False):
    output = io.StringIO(newline="")
    writer = csv.writer(
        output, lineterminator=ending,
        quoting=csv.QUOTE_ALL if quoted else csv.QUOTE_MINIMAL,
    )
    writer.writerow(header)
    writer.writerows(rows)
    return output.getvalue()


def bits(value):
    return str(struct.unpack(">Q", struct.pack(">d", value))[0])


def epoch(text):
    return datetime.datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()


def expected(row):
    return {
        "id": str(uuid.UUID(row[0])).upper(),
        "measuredAt": epoch(row[1]), "valueBits": bits(float(row[2])),
        "unit": "mgdL" if row[3] == "mg/dL" else "umolL",
        "note": row[4] or None,
        "createdAt": epoch(row[5]), "updatedAt": epoch(row[6]),
    }


def valid(name, rows=None, text=None, **kwargs):
    rows = rows or [BASE]
    text = text if text is not None else encode_csv(rows, **kwargs)
    fixtures.append({
        "name": name, "data": base64.b64encode(text.encode()).decode(),
        "records": [expected(row) for row in rows],
    })


def invalid(name, text, error, line=None, column=None):
    data = text if isinstance(text, bytes) else text.encode()
    fixtures.append({
        "name": name, "data": base64.b64encode(data).decode(),
        "error": error, "line": line, "column": column,
    })


valid("standard UTF-8, commas, escaped quotes and multiline Unicode note")
valid("CRLF records", ending="\r\n")
valid("all fields and header quoted", quoted=True)
valid("no terminal newline", text=encode_csv([BASE]).removesuffix("\n"))
valid("UTF-8 BOM", text="\ufeff" + encode_csv([BASE]))
for note in ["", " notes with spaces ", "\ttext\t", "line1\rline2", "line1\r\nline2", '=HYPERLINK("literal")']:
    row = BASE.copy()
    row[4] = note
    valid("note preserved " + repr(note), [row], quoted=True)
for number in [
    "5.29123456789", "392.29123456789", str(math.nextafter(1.125, math.inf)),
    str(math.nextafter(392.0, math.inf)), "1.2345678901234567", "1.2345678901234567e-10",
    "1e-300", "5e-324", "+5.25", ".5", "5.", "5E+2",
]:
    row = BASE.copy()
    row[2] = number
    valid("full precision positive number " + number, [row])
for unit in ["mg/dL", "μmol/L", "µmol/L"]:
    row = BASE.copy()
    row[3] = unit
    valid("unit " + unit, [row])
for date in [
    "2024-02-29T00:00:00Z", "2026-11-08T08:12:13.1Z",
    "2026-11-08T08:12:13.123456789Z", "2026-11-08T10:12:13.123+02:00",
    "2026-11-08T01:42:13.123-06:30", "2026-11-08T08:12:13+00:00",
    "2000-02-29T23:59:59.999Z", "9999-12-31T23:59:59Z",
]:
    row = BASE.copy()
    row[1] = date
    valid("strict ISO8601 valid " + date, [row])
row = BASE.copy()
row[0] = row[0].lower()
valid("lowercase canonical UUID", [row])
row = BASE.copy()
row[6] = row[5]
valid("equal creation/update dates", [row])

invalid("empty file", "", "emptyFile")
invalid("BOM only", "\ufeff", "emptyFile")
invalid("header only", encode_csv([]), "emptyFile")
invalid("header only without newline", ",".join(HEADER), "emptyFile")
for name, header in [
    ("wrong name", ["identifier", *HEADER[1:]]),
    ("wrong case", ["ID", *HEADER[1:]]),
    ("reordered", [HEADER[1], HEADER[0], *HEADER[2:]]),
    ("extra", HEADER + ["extra"]), ("missing", HEADER[:-1]),
    ("duplicate", [HEADER[0], HEADER[0], *HEADER[2:]]),
    ("whitespace", [HEADER[0] + " ", *HEADER[1:]]),
]:
    invalid("header " + name, encode_csv([BASE], header=header), "invalidHeader")
invalid("semicolon delimiter", ";".join(HEADER) + "\n", "invalidHeader")
invalid("tab delimiter", "\t".join(HEADER) + "\n", "invalidHeader")
invalid("blank line before header", "\n" + encode_csv([BASE]), "invalidHeader")
invalid("invalid UTF8", b"\xff\xfe\xfa", "invalidEncoding")
invalid("UTF16", encode_csv([BASE]).encode("utf-16"), "invalidEncoding")
invalid("truncated UTF8", encode_csv([BASE]).encode() + b"\xf0\x9f", "invalidEncoding")
for index, field in enumerate(HEADER):
    if field == "note":
        continue
    row = BASE.copy()
    row[index] = ""
    invalid("missing field " + field, encode_csv([row]), "invalidField", 2, field)
for number in [
    "NaN", "nan", "inf", "Infinity", "-1", "-0.0", "0", "+0", "0.000", "1e999", "1e-999",
    " 5.2", "5.2 ", "5,2", "5_2", "0x1f", "1.2.3", "１.２", "5\n",
]:
    row = BASE.copy()
    row[2] = number
    invalid("invalid number " + repr(number), encode_csv([row]), "invalidField", 2, "value")
for unit in ["mg/dl", "umol/L", "umolL", " mg/dL", "μmol/l", "nmol/L", "mg/dL "]:
    row = BASE.copy()
    row[3] = unit
    invalid("invalid unit " + repr(unit), encode_csv([row]), "invalidField", 2, "unit")
for identifier in [
    "1234567890ABCDEF1234567890ABCDEF", "{12345678-90AB-CDEF-1234-567890ABCDEF}",
    "12345678-90AG-CDEF-1234-567890ABCDEF", BASE[0] + " ", " " + BASE[0], "1",
]:
    row = BASE.copy()
    row[0] = identifier
    invalid("invalid UUID " + repr(identifier), encode_csv([row]), "invalidField", 2, "id")
invalid_dates = [
    "2026-02-29T00:00:00Z", "2026-02-30T00:00:00Z", "2026-04-31T00:00:00Z",
    "2026-00-01T00:00:00Z", "2026-13-01T00:00:00Z", "2026-01-00T00:00:00Z",
    "2026-01-32T00:00:00Z", "2026-01-01T24:00:00Z", "2026-01-01T00:60:00Z",
    "2026-01-01T00:00:60Z", "2026-01-01T00:00:00", "2026-01-01 00:00:00Z",
    "2026-01-01T00:00:00Z junk", "2026-01-01T00:00:00Z\n", " 2026-01-01T00:00:00Z",
    "2026-01-01T00:00:00.1234567890Z", "2026-01-01T00:00:00+24:00",
    "2026-01-01T00:00:00+00:60", "2026-01-01T00:00:00+0000", "0000-01-01T00:00:00Z",
    "1900-02-29T00:00:00Z", "2026-1-01T00:00:00Z", "2026-01-01T00:00Z",
]
for index in [1, 5, 6]:
    for date in invalid_dates:
        row = BASE.copy()
        row[index] = date
        invalid("invalid date " + HEADER[index] + " " + repr(date), encode_csv([row]), "invalidField", 2, HEADER[index])
row = BASE.copy()
row[6] = "2026-11-08T08:59:59.999Z"
invalid("update before creation", encode_csv([row]), "invalidDateOrder", 2)
row = BASE.copy()
row[0] = row[0].lower()
row[4] = "second"
invalid("duplicate UUID case insensitive", encode_csv([BASE, row]), "duplicateID", 4)
for name, row in [("extra field", BASE + ["extra"]), ("missing field", BASE[:-1])]:
    invalid(name, encode_csv([row]), "malformedCSV", 2)
simple = BASE.copy()
simple[4] = "plain"
simple_text = encode_csv([simple])
invalid("extra trailing blank row", simple_text + "\n", "malformedCSV", 3)
invalid("internal blank row", simple_text + "\n" + simple_text.split("\n", 1)[1], "malformedCSV", 3)
invalid("bare CR record separator", simple_text.replace("\n", "\r"), "malformedCSV", 1)
for index in [0, 2, 4]:
    row = simple.copy()
    row[index] += "\0"
    invalid("NUL in " + HEADER[index], encode_csv([row]), "malformedCSV", 2)
invalid("NUL in header", simple_text.replace("id,", "id\0,", 1), "malformedCSV", 1)
header_text = ",".join(HEADER) + "\n"
for note, name in [
    ('"unterminated', "unterminated quote"),
    ('unquoted"quote', "quote in unquoted field"),
    ('"closed"garbage', "text after closing quote"),
    ('"closed" ', "space after closing quote"),
]:
    text = header_text + ",".join(simple[:4]) + "," + note + "," + ",".join(simple[5:]) + "\n"
    invalid(name, text, "malformedCSV", 2)
row = simple.copy()
row[0] = "00000000-0000-0000-0000-000000000002"
row[2] = "bad"
invalid("physical line after multiline note", encode_csv([BASE, row]), "invalidField", 4, "value")
long_rows = []
for index in range(1000):
    row = simple.copy()
    row[0] = str(uuid.UUID(int=index + 1))
    long_rows.append(row)
valid("one thousand valid rows", long_rows)
row = simple.copy()
row[0] = str(uuid.UUID(int=1001))
row[2] = "bad"
invalid("invalid final row after one thousand valid rows", encode_csv([*long_rows, row]), "invalidField", 1002, "value")

units = (ROOT / "UricLog/Models/Unit.swift").read_text()
swift = "import Foundation\n" + units[units.index("enum UricUnit:"):units.index("enum AppSettingsKey")]
swift += r'''
struct ActiveLanguage { let locale: Locale }
enum AppLanguage { static var selected = ActiveLanguage(locale: Locale(identifier: "en-US")) }
enum L10n {
    static func string(_ key: String) -> String { key }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        key + ":" + arguments.map { String(describing: $0) }.joined(separator: ":")
    }
}
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
swift += (ROOT / "UricLog/Utils/CSVImporter.swift").read_text()
swift += (ROOT / "UricLog/Utils/CSVExporter.swift").read_text()
swift += r'''
struct ExpectedRecord: Decodable {
    let id: String
    let measuredAt: Double
    let valueBits: String
    let unit: String
    let note: String?
    let createdAt: Double
    let updatedAt: Double
}
struct Fixture: Decodable {
    let name: String
    let data: Data
    let records: [ExpectedRecord]?
    let error: String?
    let line: Int?
    let column: String?
}
func details(_ error: CSVImporter.ImportError) -> (String, Int?, String?) {
    switch error {
    case .invalidEncoding: return ("invalidEncoding", nil, nil)
    case .invalidHeader: return ("invalidHeader", nil, nil)
    case .emptyFile: return ("emptyFile", nil, nil)
    case .malformedCSV(let line): return ("malformedCSV", line, nil)
    case .invalidField(let column, let line): return ("invalidField", line, column)
    case .duplicateID(let line): return ("duplicateID", line, nil)
    case .invalidDateOrder(let line): return ("invalidDateOrder", line, nil)
    }
}
let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let languages = ["en-US", "zh-Hans", "de", "es", "fr", "it", "pt-PT"]
for language in languages {
    AppLanguage.selected = ActiveLanguage(locale: Locale(identifier: language))
    for fixture in fixtures {
        do {
            let document = try CSVImporter.parse(data: fixture.data)
            guard let expected = fixture.records else { fatalError("Unexpected success: \(fixture.name)") }
            assert(document.records.count == expected.count, fixture.name)
            for (record, reference) in zip(document.records, expected) {
                assert(record.id.uuidString == reference.id, fixture.name)
                assert(record.value.bitPattern == UInt64(reference.valueBits), fixture.name)
                assert(record.unit.rawValue == reference.unit, fixture.name)
                assert(record.note == reference.note, fixture.name)
                assert(abs(record.measuredAt.timeIntervalSince1970 - reference.measuredAt) <= 0.000001, fixture.name)
                assert(abs(record.createdAt.timeIntervalSince1970 - reference.createdAt) <= 0.000001, fixture.name)
                assert(abs(record.updatedAt.timeIntervalSince1970 - reference.updatedAt) <= 0.000001, fixture.name)
            }
        } catch let error as CSVImporter.ImportError {
            guard let expected = fixture.error else { fatalError("Unexpected rejection: \(fixture.name): \(error)") }
            let (code, line, column) = details(error)
            assert(code == expected, "\(fixture.name): \(code) != \(expected)")
            assert(line == fixture.line, "\(fixture.name): line \(String(describing: line)) != \(String(describing: fixture.line))")
            assert(column == fixture.column, fixture.name)
            assert(error.errorDescription?.isEmpty == false, fixture.name)
        }
    }
    print("PASS", fixtures.count, "strict CSV fixtures", language)
}
let values: [Double] = [5.29123456789, 392.29123456789, 1.125.nextUp, 392.0.nextUp,
                        1.2345678901234567, 1234.5678901234567, 1.2345678901234567e-10, 5.29123456789e-12]
let notes: [String?] = [nil, "", "text, comma", "quote \"", "multi\nline", "CRLF\r\n", "caffè 中文 🧪", " literal "]
let records = values.enumerated().map { index, value in
    UricAcidRecordEntity(
        id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
        measuredAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
        value: value, unit: index % 2 == 0 ? .mgdL : .umolL, note: notes[index],
        createdAt: Date(timeIntervalSince1970: 1_700_000_100 + Double(index)),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_200 + Double(index))
    )
}
for language in languages {
    AppLanguage.selected = ActiveLanguage(locale: Locale(identifier: language))
    for outputUnit in UricUnit.allCases {
        let url = try CSVExporter.export(records: Array(records.reversed()), preferredUnit: outputUnit)
        let imported = try CSVImporter.parse(data: Data(contentsOf: url)).records
        assert(imported.count == records.count)
        for (record, source) in zip(imported, records) {
            let expected = UricUnit.convert(value: source.value, from: source.unit, to: outputUnit)
            assert(record.id == source.id)
            assert(record.value.bitPattern == expected.bitPattern)
            assert(record.unit == outputUnit)
            assert((record.note ?? "") == (source.note ?? ""))
            assert(record.measuredAt == source.measuredAt)
            assert(record.createdAt == source.createdAt)
            assert(record.updatedAt == source.updatedAt)
        }
    }
}
print("PASS 112 actual exporter/importer numeric bit-pattern round trips, metadata and notes")
'''

with tempfile.TemporaryDirectory(prefix="uriclog-import-tests-") as directory:
    path = pathlib.Path(directory)
    source = path / "main.swift"
    source.write_text(swift)
    data = path / "fixtures.json"
    data.write_text(json.dumps(fixtures, ensure_ascii=False))
    executable = path / "csv-import-tests"
    subprocess.run(
        ["swiftc", "-module-cache-path", str(path / "module-cache"), str(source), "-o", str(executable)],
        check=True,
    )
    environment = dict(os.environ, TMPDIR=str(path) + "/")
    subprocess.run([str(executable), str(data)], env=environment, check=True)
