"""Verify two-decimal editing and preservation of unchanged saved values."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / "UricLog/Views/RecordEditorView.swift").read_text()
start = source.index("enum MeasurementValueText {")
end = source.index("\n}\n", start) + 3
parser_start = source.index("    private var parsedValue: Double? {")
parser_end = source.index("\n    }", parser_start) + len("\n    }")
editor_parser = source[parser_start:parser_end].replace("private var", "var", 1)
swift = "import Foundation\n" + source[start:end] + r"""
struct TestRecord {
    let value: Double
    let unit: Int
}
enum AppLanguage {
    struct Language { let locale: Locale }
    static var selected = Language(locale: Locale(identifier: "en-US"))
}
struct EditorParsingHarness {
    let record: TestRecord?
    let selectedUnit: Int
    let valueText: String
""" + editor_parser + r"""
}
for identifier in ["en-US", "zh-Hans", "de", "es", "fr", "it", "pt-PT"] {
    let locale = Locale(identifier: identifier)
    AppLanguage.selected = AppLanguage.Language(locale: locale)
    let decimalSeparator = locale.decimalSeparator ?? "."
    for (value, expected) in [
        (5.29, "5.29"), (5.2, "5.20"), (5.0, "5.00"),
        (392.29, "392.29"), (392.0, "392.00"),
        (6.59045057162, "6.59"), (5.29123456789, "5.29"),
        (1234.5678, "1234.57"), (1.125, "1.12"), (1.225, "1.22"),
        (1.375, "1.38"), (2.675, "2.68")
    ] {
        let text = MeasurementValueText.editing(value, locale: locale)
        let expectedText = expected.replacingOccurrences(of: ".", with: decimalSeparator)
        assert(text == expectedText, "\(identifier): \(value) -> \(text), expected \(expectedText)")
        let preserved = MeasurementValueText.valueForSaving(text, originalValue: value, locale: locale)
        assert(preserved == value, "Saving an unchanged reading must preserve \(value)")
        let newValue = MeasurementValueText.valueForSaving(text, originalValue: nil, locale: locale)
        assert(newValue == Double(expected), "New readings must use the displayed numeric value")
    }
    let changedText = "5.87".replacingOccurrences(of: ".", with: decimalSeparator)
    assert(MeasurementValueText.valueForSaving(changedText, originalValue: 5.29123456789, locale: locale) == 5.87)
    let explicitlyRetyped = "5.290".replacingOccurrences(of: ".", with: decimalSeparator)
    assert(MeasurementValueText.valueForSaving(explicitlyRetyped, originalValue: 5.29123456789, locale: locale) == 5.29)
    for original in [5.29123456789, 392.29123456789, 1.125.nextUp] {
        let completeText = String(original).replacingOccurrences(of: ".", with: decimalSeparator)
        let newReading = MeasurementValueText.valueForSaving(completeText, originalValue: nil, locale: locale)
        let editedReading = MeasurementValueText.valueForSaving(completeText, originalValue: 5.2, locale: locale)
        assert(newReading?.bitPattern == original.bitPattern, "New input must retain every available digit")
        assert(editedReading?.bitPattern == original.bitPattern, "Edited input must retain every available digit")
        for originalUnit in 0...1 {
            for selectedUnit in 0...1 {
                let record = TestRecord(value: original, unit: originalUnit)
                let unchangedEditor = EditorParsingHarness(
                    record: record, selectedUnit: selectedUnit,
                    valueText: MeasurementValueText.editing(original, locale: locale)
                )
                assert(unchangedEditor.parsedValue?.bitPattern == original.bitPattern,
                       "Note/date/unit-only edits must preserve hidden decimals")
                let changedEditor = EditorParsingHarness(
                    record: TestRecord(value: 5.2, unit: originalUnit),
                    selectedUnit: selectedUnit, valueText: completeText
                )
                assert(changedEditor.parsedValue?.bitPattern == original.bitPattern,
                       "The editor must save every digit of changed input")
            }
        }
        let targetFormat = FloatingPointFormatStyle<Double>.number.locale(locale).precision(.fractionLength(2))
        let parsedTarget = try targetFormat.parseStrategy.parse(completeText)
        assert(parsedTarget.bitPattern == original.bitPattern, "Display precision must not limit target input")
    }
    print("PASS two-decimal display, unchanged-value preservation and edited values", identifier)
}
assert(MeasurementValueText.editing(5.29, locale: Locale(identifier: "it")) == "5,29")
assert(MeasurementValueText.editing(5.2, locale: Locale(identifier: "en-US")) == "5.20")
assert(MeasurementValueText.parse("5,29") == 5.29)
assert(MeasurementValueText.parse("5.29") == 5.29)
assert(MeasurementValueText.parse(" 5,29 \n") == 5.29)
for invalid in ["", "abc", "5,2,9", "5.2.9", "nan", "inf", "1e999"] {
    assert(MeasurementValueText.parse(invalid) == nil, invalid)
    assert(MeasurementValueText.valueForSaving(invalid, originalValue: 5.29123456789, locale: Locale(identifier: "it")) == nil, invalid)
    assert(MeasurementValueText.valueForSaving(invalid, originalValue: nil, locale: Locale(identifier: "en-US")) == nil, invalid)
}
print("PASS two decimal places, comma/dot input and invalid values")
"""
with tempfile.TemporaryDirectory() as directory:
    path = pathlib.Path(directory) / "test.swift"
    path.write_text(swift)
    subprocess.run(
        ["swift", "-module-cache-path", str(pathlib.Path(directory) / "module-cache"), str(path)],
        check=True,
    )
