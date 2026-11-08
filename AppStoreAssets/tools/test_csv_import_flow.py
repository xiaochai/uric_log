"""Test the actual CSV file reader and import control methods on macOS.

SwiftUI state is replaced by reference-backed storage and persistence by a spy.
The separate store regression tests exercise real Core Data transactions.
Native SwiftUI/UIKit rendering and document-picker interaction are not included.
NSFileCoordinator requires access to the macOS file-coordination service.
"""
import pathlib
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[2]


def swift_declaration(source, marker):
    start = source.index(marker)
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
        end += 1
    return source[start:end]


settings = (ROOT / "UricLog/Views/SettingsView.swift").read_text()
units = (ROOT / "UricLog/Models/Unit.swift").read_text()
store = (ROOT / "UricLog/Persistence/CSVImportStore.swift").read_text()
swift = "\n".join([
    "import Foundation",
    """
enum L10n {
    static func string(_ key: String) -> String { key }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        key + ":" + String(describing: arguments.first!)
    }
}
""",
    swift_declaration(units, "enum UricUnit:"),
    (ROOT / "UricLog/Utils/CSVImporter.swift").read_text(),
    swift_declaration(settings, "private enum CSVImportFileReader {").replace(
        "private enum", "enum", 1,
    ),
    swift_declaration(settings, "private struct CSVImportPreview:").replace(
        "private struct", "struct", 1,
    ),
    swift_declaration(settings, "private struct CSVImportNotice {").replace(
        "private struct", "struct", 1,
    ),
    swift_declaration(store, "enum CSVImportMode:"),
    """
struct StubContainer {}
struct StubPersistence { let container = StubContainer() }
@MainActor enum CSVImportStore {
    enum TestError: LocalizedError {
        case rejected
        var errorDescription: String? { "save-rejected" }
    }
    static var calls: [String] = []
    static var failNext = false
    static func apply(
        _ document: CSVImportDocument, mode: CSVImportMode, to container: StubContainer
    ) async throws -> Int {
        switch mode {
        case .append: calls.append("append")
        case .replace: calls.append("replace")
        }
        await Task.yield()
        if failNext { failNext = false; throw TestError.rejected }
        return document.records.count
    }
}
@propertyWrapper struct RefState<Value> {
    private final class Storage {
        var value: Value
        init(_ value: Value) { self.value = value }
    }
    private let storage: Storage
    init(wrappedValue: Value) { storage = Storage(wrappedValue) }
    var wrappedValue: Value {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }
}
@MainActor struct ImportFlowHarness {
    @RefState var isValidatingImport = false
    @RefState var isImporting = false
    @RefState var importSaveError: String? = nil
    @RefState var importNotice: CSVImportNotice? = nil
    @RefState var pendingImport: CSVImportPreview? = nil
    @RefState var completedImportCount: Int? = nil
    let persistence = StubPersistence()
""",
    *[
        swift_declaration(settings, "private func " + name + "(").replace(
            "private func", "func", 1,
        )
        for name in ("prepareCSVImport", "performCSVImport", "importReviewDismissed")
    ],
    r'''
}
@MainActor func waitUntil(_ description: String, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(15)
    while !condition() {
        precondition(Date() < deadline, "Timed out waiting for \(description)")
        await Task.yield()
    }
}
@main struct TestRunner {
    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let valid = directory.appendingPathComponent("valid.csv")
        let invalid = directory.appendingPathComponent("invalid.csv")
        let selected = directory.appendingPathComponent("selected.csv")
        let header = "id,measured_at,value,unit,note,created_at,updated_at\n"
        let row = "12345678-1234-1234-1234-123456789ABC,2026-11-08T10:11:12.123Z,5.29123456789,mg/dL,\"test, note\nsecond line\",2026-11-08T10:11:12.123Z,2026-11-08T11:11:12.123Z\n"
        try (header + row).write(to: selected, atomically: true, encoding: .utf8)
        let document = try CSVImportFileReader.read(selected)
        assert(document.records.count == 1)
        assert(document.records[0].value.bitPattern == 5.29123456789.bitPattern)
        assert(document.records[0].note == "test, note\nsecond line")
        print("PASS coordinated local file, complete precision and multiline note")

        try Data([0xFF, 0xFE, 0xFF]).write(to: selected)
        do {
            _ = try CSVImportFileReader.read(selected)
            fatalError("Corrupt UTF-8 file must fail")
        } catch CSVImporter.ImportError.invalidEncoding {}
        try (header + row + "bad,invalid,NaN,kg,,invalid,invalid\n")
            .write(to: selected, atomically: true, encoding: .utf8)
        do {
            _ = try CSVImportFileReader.read(selected)
            fatalError("Invalid last row must reject the entire file")
        } catch CSVImporter.ImportError.invalidField(let column, let line) {
            assert(column == "id" && line == 4)
        }
        print("PASS reader rejects corrupt text and invalid last physical line")

        for url in [directory.appendingPathComponent("missing.csv"), directory] {
            do {
                _ = try CSVImportFileReader.read(url)
                fatalError("Missing file or directory must fail")
            } catch {
                assert(error.localizedDescription == "CSV_IMPORT_READ_ERROR")
            }
        }
        try (header + row).write(to: selected, atomically: true, encoding: .utf8)
        let reread = try CSVImportFileReader.read(selected)
        assert(reread.records.count == 1)
        try FileManager.default.removeItem(at: selected)
        assert(!FileManager.default.fileExists(atPath: selected.path))
        print("PASS read errors, reread and cleanup after file coordination")

        try (header + row).write(to: valid, atomically: true, encoding: .utf8)
        try (header + row + "bad-last-row\n")
            .write(to: invalid, atomically: true, encoding: .utf8)
        let harness = ImportFlowHarness()
        harness.prepareCSVImport(.success([valid]))
        await waitUntil("valid preview") { !harness.isValidatingImport }
        assert(harness.pendingImport?.document.records.count == 1)
        assert(harness.pendingImport?.document.records[0].value.bitPattern == 5.29123456789.bitPattern)
        assert(CSVImportStore.calls.isEmpty, "Preparing a file must not write")
        harness.pendingImport = nil
        harness.importReviewDismissed()
        assert(harness.importNotice == nil && CSVImportStore.calls.isEmpty)
        print("PASS valid preview and cancel do not save or delete")

        harness.prepareCSVImport(.success([invalid]))
        await waitUntil("invalid-file notice") { !harness.isValidatingImport }
        assert(harness.pendingImport == nil && harness.importNotice?.title == "IMPORT_FAILURE_TITLE")
        assert(CSVImportStore.calls.isEmpty)
        harness.importNotice = nil
        harness.prepareCSVImport(.failure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)))
        harness.prepareCSVImport(.success([]))
        assert(harness.importNotice == nil && harness.pendingImport == nil && CSVImportStore.calls.isEmpty)
        print("PASS invalid file and picker cancellation leave archive untouched")

        harness.prepareCSVImport(.success([valid]))
        await waitUntil("append review") { !harness.isValidatingImport }
        harness.performCSVImport(.append)
        assert(harness.isImporting)
        harness.performCSVImport(.replace)
        await waitUntil("append save") { !harness.isImporting }
        assert(CSVImportStore.calls == ["append"], "Concurrent second choice must be ignored")
        assert(harness.pendingImport == nil && harness.completedImportCount == 1)
        assert(harness.importNotice == nil, "Success must wait for review dismissal")
        harness.importReviewDismissed()
        assert(harness.importNotice?.title == "IMPORT_SUCCESS_TITLE")
        assert(harness.importNotice?.message == "IMPORT_SUCCESS_MESSAGE:1")
        assert(harness.completedImportCount == nil)
        print("PASS append runs once and success waits for review dismissal")

        harness.importNotice = nil
        harness.prepareCSVImport(.success([valid]))
        await waitUntil("retry review") { !harness.isValidatingImport }
        CSVImportStore.failNext = true
        harness.performCSVImport(.append)
        await waitUntil("save failure") { !harness.isImporting }
        assert(harness.importSaveError == "save-rejected")
        assert(harness.pendingImport != nil && harness.completedImportCount == nil)
        assert(harness.importNotice == nil)
        print("PASS save error preserves review for retry or cancellation")

        harness.performCSVImport(.replace)
        await waitUntil("replacement retry") { !harness.isImporting }
        assert(CSVImportStore.calls == ["append", "append", "replace"])
        assert(harness.importSaveError == nil && harness.pendingImport == nil)
        harness.importReviewDismissed()
        assert(harness.importNotice?.message == "IMPORT_SUCCESS_MESSAGE:1")
        print("PASS replacement retry clears the error and reports success")
    }
}
''',
])

with tempfile.TemporaryDirectory(prefix="uriclog-import-flow-") as directory:
    path = pathlib.Path(directory)
    source = path / "main.swift"
    executable = path / "test"
    source.write_text(swift)
    subprocess.run([
        "swiftc", "-parse-as-library", "-module-cache-path", str(path / "module-cache"),
        str(source), "-o", str(executable),
    ], check=True, timeout=180)
    subprocess.run([str(executable), str(path)], check=True, timeout=90)
