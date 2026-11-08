"""Verify actual Swift conversions, chart statistics, colors and axis domains."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
units = (root / "UricLog/Models/Unit.swift").read_text()
trends = (root / "UricLog/Views/TrendsView.swift").read_text()
source = (
    "import Foundation\n"
    + units[units.index("enum UricUnit:"):units.index("enum AppSettingsKey")]
    + trends[trends.index("enum TrendYAxis {"):trends.index("private struct StatItemView:")]
    + """
// Only the green/non-green result matters for the classification regression.
struct Color: Equatable {
    let isGreen: Bool
    static let green = Color(isGreen: true)
    init(isGreen: Bool) { self.isGreen = isGreen }
    init(hue: Double, saturation: Double, brightness: Double) { isGreen = false }
}
"""
    + trends[trends.index("private struct TrendPoint {"):]
)
source += r"""
func assertClose(_ actual: Double, _ expected: Double, ulps: Double = 4) {
    assert(actual.isFinite && expected.isFinite)
    let tolerance = max(actual.ulp, expected.ulp) * ulps
    assert(abs(actual - expected) <= tolerance,
           "Precision lost: \(actual) vs \(expected), tolerance \(tolerance)")
}

// Independent reference constants calculated with 60-digit decimal arithmetic.
for (value, expected) in [(0.0, 0.0), (5.29, 314.67435368326628410038),
                          (6.0, 356.90852969746648480194), (7.2, 428.29023563695978176233),
                          (5.29123456789, 314.74779165167155135646),
                          (0.000000123456789, 0.00000734379684052672560813)] {
    assertClose(UricUnit.convert(value: value, from: .mgdL, to: .umolL), expected)
}
for (value, expected) in [(0.0, 0.0), (100.23, 1.6849695369),
                          (314.67, 5.2899268101), (392.0, 6.58992376),
                          (428.0, 7.19512084), (392.29123456789, 6.5948197130578358267)] {
    assertClose(UricUnit.convert(value: value, from: .umolL, to: .mgdL), expected)
}
for unit in UricUnit.allCases {
    let other: UricUnit = unit == .mgdL ? .umolL : .mgdL
    for original in [0.0, -0.0, 0.000000123456789, 1.125, 5.29123456789,
                     392.29123456789, 1200.1234567890123, (2000.0).nextUp] {
        assert(UricUnit.convert(value: original, from: unit, to: unit).bitPattern == original.bitPattern)
        let converted = UricUnit.convert(value: original, from: unit, to: other)
        let compatible = UricUnit.convertWithoutRounding(value: original, from: unit, to: other)
        assert(converted.bitPattern == compatible.bitPattern,
               "Conversion entry points must preserve the same precision")
        let recovered = UricUnit.convert(value: converted, from: other, to: unit)
        assertClose(recovered, original)
    }
}
assert(UricUnit.convert(value: 392, from: .umolL, to: .mgdL) != 6.59,
       "Conversions must retain precision until the UI formats them")
print("PASS full-precision formulas, conversion aliases and round trips")

let english = Locale(identifier: "en-US")
for value in [1.125, 1.225, 1.375, 2.675] {
    let originalText = value.formatted(.number.locale(english).precision(.fractionLength(2)))
    let micromoles = UricUnit.convertWithoutRounding(value: value, from: .mgdL, to: .umolL)
    let converted = UricUnit.convertWithoutRounding(value: micromoles, from: .umolL, to: .mgdL)
    let convertedText = converted.formatted(.number.locale(english).precision(.fractionLength(2)))
    assert(originalText == convertedText, "Equivalent readings must use the same display rounding")
}
for unit in UricUnit.allCases {
    for (value, upper, expectedGreen) in [(428.0, 428.0, true), (428.01, 428.0, false),
                                         (357.0, 357.0, true), (357.01, 357.0, false)] {
        let point = TrendPoint(
            recordID: UUID(), measuredAt: Date(),
            value: UricUnit.convert(value: value, from: .umolL, to: unit),
            valueInMicromoles: value, normalUpperUmol: upper
        )
        assert((point.valueColor == .green) == expectedGreen,
               "Changing display units must not change classification of \(value)")
    }
    let stats = TrendStats.calculate(
        valuesInMicromoles: [300, 300, 304], targetInMicromoles: nil, unit: unit
    )
    let expectedAverage = unit == .mgdL ? "5.07" : "301.33"
    assert(stats.average.formatted(.number.locale(english).precision(.fractionLength(2))) == expectedAverage)
    assert(stats.min <= stats.average && stats.average <= stats.max)
    let overTarget = TrendStats.calculate(
        valuesInMicromoles: [420.1], targetInMicromoles: 420, unit: unit
    )
    assert(overTarget.targetRate == 0, "A reading above the target must remain above it in either unit")
    let atTarget = TrendStats.calculate(
        valuesInMicromoles: [419.9, 420, 420.1], targetInMicromoles: 420, unit: unit
    )
    assert(atTarget.targetRate == 2.0 / 3.0)
    let empty = TrendStats.calculate(valuesInMicromoles: [], targetInMicromoles: nil, unit: unit)
    assert(empty.average == 0 && empty.min == 0 && empty.max == 0 && empty.latest == 0 && empty.targetRate == 0)
}
let targetInMilligrams = UricUnit.convertWithoutRounding(value: 420, from: .umolL, to: .mgdL)
let targetRoundTrip = UricUnit.convertWithoutRounding(value: targetInMilligrams, from: .mgdL, to: .umolL)
assert(abs(targetRoundTrip - 420) < 1e-10, "Changing target units must preserve its precision")
for target in [360.0, 392.0] {
    let milligrams = UricUnit.convertWithoutRounding(value: target, from: .umolL, to: .mgdL)
    let roundTrip = UricUnit.convertWithoutRounding(value: milligrams, from: .mgdL, to: .umolL)
    for unit in UricUnit.allCases {
        let equal = TrendStats.calculate(valuesInMicromoles: [target], targetInMicromoles: roundTrip, unit: unit)
        assert(equal.targetRate == 1, "Floating-point conversion noise must not exclude a reading at the target")
        let above = TrendStats.calculate(valuesInMicromoles: [target + 1e-8], targetInMicromoles: roundTrip, unit: unit)
        assert(above.targetRate == 0, "The comparison tolerance must not hide a real increase")
    }
}
let boundaryInMilligrams = UricUnit.convertWithoutRounding(value: 428, from: .umolL, to: .mgdL)
let convertedBoundary = UricUnit.convertWithoutRounding(value: boundaryInMilligrams, from: .mgdL, to: .umolL)
private let boundaryPoint = TrendPoint(
    recordID: UUID(), measuredAt: Date(), value: boundaryInMilligrams,
    valueInMicromoles: convertedBoundary, normalUpperUmol: 428
)
assert(boundaryPoint.valueColor == .green, "Converting an original reading at the reference limit must keep it green")
print("PASS canonical classification, average, target rate and target round trip")

func check(_ values: [Double], target: Double? = nil) {
    let si = TrendYAxis.domain(values: values, target: target, unit: .umolL)
    let valuesInMilligrams = values.map { ($0 * 168.1103) / 10000 }
    let targetInMilligrams = target.map { ($0 * 168.1103) / 10000 }
    let mg = TrendYAxis.domain(
        values: valuesInMilligrams, target: targetInMilligrams, unit: .mgdL
    )
    assert(si.lowerBound >= 0 && si.upperBound > si.lowerBound)
    assert(mg.lowerBound >= 0 && mg.upperBound > mg.lowerBound)
    let expectedLower = (si.lowerBound * 168.1103) / 10000
    let expectedUpper = (si.upperBound * 168.1103) / 10000
    // Allow only floating-point operation noise, measured at the axis scale.
    // The scale also covers cancellation near the clamped zero lower bound.
    let floatingPointTolerance = max(expectedUpper.ulp, mg.upperBound.ulp) * 16
    assert(abs(expectedLower - mg.lowerBound) <= floatingPointTolerance)
    assert(abs(expectedUpper - mg.upperBound) <= floatingPointTolerance)
    for value in values.filter(\.isFinite) where value >= 0 {
        assert(si.contains(value))
    }
    if let target, target.isFinite, target >= 0 {
        assert(si.contains(target))
    }
    for value in valuesInMilligrams.filter(\.isFinite) where value >= 0 {
        assert(mg.contains(value))
    }
    if let targetInMilligrams, targetInMilligrams.isFinite, targetInMilligrams >= 0 {
        assert(mg.contains(targetInMilligrams))
    }
    print("PASS", values, target as Any, si, mg)
}
check([392, 398, 407, 414, 421])
check([392, 398, 407, 414, 421], target: 420)
check([392, 398, 407, 414, 421], target: 600)
check([392.1234, 398.9876, 407.0049, 414.0051, 421.6789], target: 420.1234)
check([400])
check([400, 400, 400])
check([0])
check([0, 1])
check([6.5, (6.5).nextUp])
check([0.000000123456789, 0.000000987654321])
check([])
check([Double.nan, Double.infinity, 400], target: Double.nan)
check([1, 2000])
let narrow = TrendYAxis.domain(values: [6.6, 6.7, 6.8, 7.1], target: nil, unit: .mgdL)
assert(narrow.upperBound - narrow.lowerBound < 1)
print("PASS mg/dL narrow span", narrow)
"""

with tempfile.TemporaryDirectory() as directory:
    path = pathlib.Path(directory) / "axis-tests.swift"
    path.write_text(source)
    subprocess.run(
        ["swift", "-module-cache-path", str(pathlib.Path(directory) / "module-cache"), str(path)],
        check=True,
    )
