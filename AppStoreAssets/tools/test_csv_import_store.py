"""Verify real SQLite imports, atomic failure, UI merging and full-precision data."""
import os
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


units = (ROOT / "UricLog/Models/Unit.swift").read_text()
persistence = (ROOT / "UricLog/Persistence/Persistence.swift").read_text()
model = swift_declaration(persistence, "private static func makeManagedObjectModel()")
model = "enum Persistence {\n" + model.replace("private static func", "static func", 1) + "\n}"
swift = "\n".join([
    "import Foundation\nimport CoreData\nimport Darwin",
    """
enum L10n {
    static func string(_ key: String) -> String { key }
    static func format(_ key: String, _ arguments: CVarArg...) -> String { key }
}
""",
    swift_declaration(units, "enum UricUnit:"),
    (ROOT / "UricLog/Models/UricAcidRecord.swift").read_text(),
    model,
    (ROOT / "UricLog/Utils/CSVExporter.swift").read_text(),
    (ROOT / "UricLog/Utils/CSVImporter.swift").read_text(),
    (ROOT / "UricLog/Persistence/CSVImportStore.swift").read_text(),
    r'''
func require(_ condition: @autoclosure () throws -> Bool, _ message: String = "Requirement failed") rethrows {
    let result = try condition()
    precondition(result, message)
}

struct Row {
    let id: UUID
    let value: Double
    let unit: UricUnit
    let note: String

    init(_ index: Int, _ value: Double, _ unit: UricUnit, _ note: String = "") {
        self.id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!
        self.value = value
        self.unit = unit
        self.note = note
    }

    var csv: String {
        let escaped = note.replacingOccurrences(of: "\"", with: "\"\"")
        return "\(id.uuidString),2026-10-25T09:42:13.123Z,\(String(value)),\(unit.displayName),\"\(escaped)\",2026-10-26T10:30:00.456Z,2026-10-27T11:31:01.789Z"
    }
}

let header = "id,measured_at,value,unit,note,created_at,updated_at\n"

func csv(_ rows: [Row]) -> Data {
    Data((header + rows.map(\.csv).joined(separator: "\n") + "\n").utf8)
}

func document(_ rows: [Row]) throws -> CSVImportDocument {
    try CSVImporter.parse(data: csv(rows))
}

struct Snapshot: Equatable {
    let id: UUID
    let valueBits: UInt64
    let unit: String
    let note: String?
    let measuredBits: UInt64
    let createdBits: UInt64
    let updatedBits: UInt64

    init(_ record: UricAcidRecordEntity) {
        id = record.id
        valueBits = record.value.bitPattern
        unit = record.unitRawValue
        note = record.note
        measuredBits = record.measuredAt.timeIntervalSinceReferenceDate.bitPattern
        createdBits = record.createdAt.timeIntervalSinceReferenceDate.bitPattern
        updatedBits = record.updatedAt.timeIntervalSinceReferenceDate.bitPattern
    }

    init(_ record: CSVImportRecord) {
        id = record.id
        valueBits = record.value.bitPattern
        unit = record.unit.rawValue
        note = record.note
        measuredBits = record.measuredAt.timeIntervalSinceReferenceDate.bitPattern
        createdBits = record.createdAt.timeIntervalSinceReferenceDate.bitPattern
        updatedBits = record.updatedAt.timeIntervalSinceReferenceDate.bitPattern
    }
}

func stored(_ container: NSPersistentContainer) throws -> [Snapshot] {
    let context = container.newBackgroundContext()
    return try context.performAndWait {
        let request = NSFetchRequest<UricAcidRecordEntity>(entityName: "UricAcidRecordEntity")
        return try context.fetch(request).map(Snapshot.init).sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

func expected(_ document: CSVImportDocument) -> [Snapshot] {
    document.records.map(Snapshot.init).sorted { $0.id.uuidString < $1.id.uuidString }
}

final class ResultsObserver: NSObject, NSFetchedResultsControllerDelegate {
    var changes = 0

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<any NSFetchRequestResult>) {
        changes += 1
    }
}

@MainActor
func container(
    _ url: URL, readOnly: Bool = false, rejectLargeValues: Bool = false,
    automaticallyMerges: Bool = true
) throws -> NSPersistentContainer {
    let model = Persistence.makeManagedObjectModel()
    if rejectLargeValues {
        let attribute = model.entities[0].attributesByName["value"]!
        attribute.setValidationPredicates([NSPredicate(format: "SELF < 100")], withValidationWarnings: ["Injected test failure"])
    }
    let container = NSPersistentContainer(name: "ImportTests", managedObjectModel: model)
    let description = NSPersistentStoreDescription(url: url)
    description.type = NSSQLiteStoreType
    description.shouldAddStoreAsynchronously = false
    if readOnly { description.setOption(true as NSNumber, forKey: NSReadOnlyPersistentStoreOption) }
    container.persistentStoreDescriptions = [description]
    var failure: Error?
    container.loadPersistentStores { _, error in failure = error }
    if let failure { throw failure }
    container.viewContext.automaticallyMergesChangesFromParent = automaticallyMerges
    container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    return container
}

@MainActor
func close(_ container: NSPersistentContainer) throws {
    container.viewContext.reset()
    for store in container.persistentStoreCoordinator.persistentStores {
        try container.persistentStoreCoordinator.remove(store)
    }
}

@MainActor
func seed(_ container: NSPersistentContainer, index: Int = 1) throws {
    let entity = NSEntityDescription.entity(forEntityName: "UricAcidRecordEntity", in: container.viewContext)!
    let record = UricAcidRecordEntity(entity: entity, insertInto: container.viewContext)
    record.id = Row(index, 1, .mgdL).id
    record.measuredAt = Date(timeIntervalSince1970: 1_700_000_000.125)
    record.value = 5.29123456789
    record.unit = .mgdL
    record.note = "Existing measurement"
    record.createdAt = Date(timeIntervalSince1970: 1_700_000_000.25)
    record.updatedAt = Date(timeIntervalSince1970: 1_700_000_001.5)
    try container.viewContext.save()
}

@MainActor
func expectFailure(
    _ expectedError: CSVImportStore.ImportError,
    _ document: CSVImportDocument,
    _ mode: CSVImportMode,
    _ container: NSPersistentContainer
) async throws {
    let before = try stored(container)
    do {
        _ = try await CSVImportStore.apply(document, mode: mode, to: container)
        preconditionFailure("Expected the entire import to fail")
    } catch let error as CSVImportStore.ImportError {
        precondition(error.errorDescription == expectedError.errorDescription,
                     "Unexpected error: \(error) instead of \(expectedError)")
    }
    try require(try stored(container) == before, "An import failure must not change any persisted row")
}

@main
struct ImportStoreTests {
    @MainActor
    static func main() async throws {
        setbuf(stdout, nil)
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let url = directory.appendingPathComponent("main.sqlite")
        var store = try container(url)
        try seed(store)
        let original = try stored(store)
        let request = NSFetchRequest<UricAcidRecordEntity>(entityName: "UricAcidRecordEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "measuredAt", ascending: true)]
        let controller = NSFetchedResultsController(
            fetchRequest: request, managedObjectContext: store.viewContext,
            sectionNameKeyPath: nil, cacheName: nil
        )
        let observer = ResultsObserver()
        controller.delegate = observer
        try controller.performFetch()
        precondition(controller.fetchedObjects?.count == 1)

        let rows = [
            Row(200, 5.29123456789, .mgdL, "Before breakfast, \"fasting\""),
            Row(201, 392.29123456789, .umolL, "Line one\nLine two"),
            Row(202, 1.125.nextUp, .mgdL, "Unicode caffè 中文 🧪"),
            Row(203, 392.0.nextUp, .umolL, "Windows\r\nline break"),
            Row(204, 1.2345678901234567, .mgdL, " leading and trailing spaces "),
            Row(205, 1234.5678901234567, .umolL),
            Row(206, 1.2345678901234567e-10, .mgdL),
            Row(207, 1.2345678901234567e-10, .umolL),
        ]
        let incoming = try document(rows)
        let appended = try await CSVImportStore.apply(incoming, mode: .append, to: store)
        precondition(appended == rows.count)
        let afterAppend = try stored(store)
        precondition(afterAppend == (original + expected(incoming)).sorted { $0.id.uuidString < $1.id.uuidString })
        store.viewContext.processPendingChanges()
        precondition(controller.fetchedObjects?.count == 9, "The existing fetched-results controller must receive inserted rows")
        print("PASS append preserves all existing fields and all 8 imported Double bit patterns/metadata/notes")

        // A collision at the end must also reject every preceding new row.
        try await expectFailure(.existingRecords, document([Row(999, 4.123456789, .mgdL), rows.last!]), .append, store)
        precondition(!store.viewContext.hasChanges)
        print("PASS duplicate append is rejected without partial inserts")

        for mode in [CSVImportMode.append, .replace] {
            let before = try stored(store)
            let broken = String(decoding: csv([Row(998, 4.123456789, .mgdL)]), as: UTF8.self)
                + Row(997, 4.123456789, .mgdL).csv.replacingOccurrences(of: ",4.123456789,", with: ",nan,") + "\n"
            do {
                let invalid = try CSVImporter.parse(data: Data(broken.utf8))
                _ = try await CSVImportStore.apply(invalid, mode: mode, to: store)
                preconditionFailure("Invalid last row must reject the entire file before applying either mode")
            } catch is CSVImporter.ImportError {}
            try require(try stored(store) == before)
            do {
                let empty = try CSVImporter.parse(data: Data(header.utf8))
                _ = try await CSVImportStore.apply(empty, mode: mode, to: store)
                preconditionFailure("An empty file must not clear the archive")
            } catch is CSVImporter.ImportError {}
            try require(try stored(store) == before)
        }
        print("PASS invalid last row and empty files cannot modify or clear existing data in either mode")

        let replacement = try document([rows[0], Row(300, 6.123456789012345, .mgdL, "replacement")])
        let replaced = try await CSVImportStore.apply(replacement, mode: .replace, to: store)
        precondition(replaced == 2)
        try require(try stored(store) == expected(replacement), "Replacement must delete all previous rows and retain imported IDs")
        store.viewContext.processPendingChanges()
        precondition(controller.fetchedObjects?.count == 2, "The existing fetched-results controller must receive deletes and inserts")
        precondition(observer.changes >= 2, "The fetched-results delegate must receive both committed imports")
        print("PASS replacement commits deletes and inserts together and refreshes fetched results")

        // Test collision detection beyond SQLite's usual 999-parameter limit.
        let manyRows = (1000..<2103).map { Row($0, Double($0) / 300.123456789, .mgdL) }
        let collidingMany = try document(manyRows + [rows[0]])
        try await expectFailure(.existingRecords, collidingMany, .append, store)
        let many = try document(manyRows)
        let largeCount = try await CSVImportStore.apply(many, mode: .append, to: store)
        precondition(largeCount == 1103)
        try require(try stored(store) == (expected(replacement) + expected(many)).sorted { $0.id.uuidString < $1.id.uuidString })
        print("PASS 1103-row append and late duplicate detection across multiple SQLite predicate chunks")

        // Ordinary editor saves must keep working after committed background deletes.
        let beforeEditorSave = try stored(store)
        let editorRecord = UricAcidRecordEntity.create(
            in: store.viewContext, measuredAt: Date(), value: 9.123456789012345,
            unit: .mgdL, note: "Created normally after import"
        )
        try store.viewContext.save()
        let afterEditorSave = try stored(store)
        precondition(afterEditorSave.count == beforeEditorSave.count + 1)
        precondition(afterEditorSave.first { $0.id == editorRecord.id }?.valueBits == 9.123456789012345.bitPattern)
        precondition(afterEditorSave.filter { $0.id != editorRecord.id } == beforeEditorSave)
        store.viewContext.delete(editorRecord)
        try store.viewContext.save()
        try require(try stored(store) == beforeEditorSave)
        print("PASS ordinary measurement creation and deletion still save correctly after replacement and append")

        // Unsaved interface changes remain intact and are never implicitly committed.
        let pending = UricAcidRecordEntity.create(
            in: store.viewContext, measuredAt: Date(), value: 8.123456789,
            unit: .mgdL, note: "Unsaved draft"
        )
        try await expectFailure(.unsavedChanges, document([Row(4000, 7.123456789, .mgdL)]), .append, store)
        precondition(store.viewContext.hasChanges && pending.isInserted && pending.note == "Unsaved draft")
        store.viewContext.rollback()
        let editedRecord = try store.viewContext.fetch(request).first!
        editedRecord.note = "Unsaved note edit"
        try await expectFailure(.unsavedChanges, document([Row(4000, 7.123456789, .mgdL)]), .replace, store)
        precondition(editedRecord.note == "Unsaved note edit" && store.viewContext.updatedObjects.contains(editedRecord))
        store.viewContext.rollback()
        let deletedRecord = try store.viewContext.fetch(request).first!
        store.viewContext.delete(deletedRecord)
        try await expectFailure(.unsavedChanges, document([Row(4000, 7.123456789, .mgdL)]), .replace, store)
        precondition(store.viewContext.deletedObjects.contains(deletedRecord))
        store.viewContext.rollback()
        print("PASS pending interface inserts, edits and persisted-row deletions are preserved and block import")

        try close(store)
        store = try container(url)
        try require(try stored(store).count == 1105)
        let reopened = try stored(store)
        precondition(reopened == (expected(replacement) + expected(many)).sorted { $0.id.uuidString < $1.id.uuidString })
        let reopenedRequest = NSFetchRequest<UricAcidRecordEntity>(entityName: "UricAcidRecordEntity")
        let fetched = try store.viewContext.fetch(reopenedRequest)
        for outputUnit in UricUnit.allCases {
            let exportURL = try CSVExporter.export(records: fetched, preferredUnit: outputUnit)
            let roundTrip = try CSVImporter.parse(data: Data(contentsOf: exportURL))
            precondition(roundTrip.records.count == fetched.count)
            let originalByID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            for record in roundTrip.records {
                let originalRecord = originalByID[record.id]!
                let expectedValue = UricUnit.convert(value: originalRecord.value, from: originalRecord.unit, to: outputUnit)
                precondition(record.value.bitPattern == expectedValue.bitPattern)
                precondition(record.unit == outputUnit && record.note == originalRecord.note)
            }
        }
        print("PASS close/reopen preserves all imported values and 2210 actual export/import values retain every Double bit")

        // Inject a real Core Data validation failure only in this test's model.
        let validationStore = try container(directory.appendingPathComponent("validation.sqlite"), rejectLargeValues: true)
        try seed(validationStore)
        let invalidForModel = try document([Row(5000, 6.123456789, .mgdL), Row(5001, 392.123456789, .umolL)])
        for mode in [CSVImportMode.append, .replace] {
            try await expectFailure(.failedToSave, invalidForModel, mode, validationStore)
            precondition(!validationStore.viewContext.hasChanges)
        }
        try close(validationStore)
        let reopenedValidation = try container(directory.appendingPathComponent("validation.sqlite"), rejectLargeValues: true)
        try require(try stored(reopenedValidation).count == 1)
        print("PASS real Core Data validation/save failures roll back both append and destructive replacement")

        // A read-only SQLite store makes the persistent-store commit itself fail.
        let readOnlyURL = directory.appendingPathComponent("readonly.sqlite")
        let writable = try container(readOnlyURL)
        try seed(writable)
        let readOnlyBefore = try stored(writable)
        try close(writable)
        let readOnly = try container(readOnlyURL, readOnly: true)
        for mode in [CSVImportMode.append, .replace] {
            try await expectFailure(.failedToSave, document([Row(6000, 7.123456789, .mgdL)]), mode, readOnly)
        }
        try require(try stored(readOnly) == readOnlyBefore)
        print("PASS read-only SQLite commit failures preserve the entire original archive in either mode")

        let manual = try container(directory.appendingPathComponent("manual.sqlite"), automaticallyMerges: false)
        try seed(manual)
        let manualController = NSFetchedResultsController(
            fetchRequest: {
                let request = NSFetchRequest<UricAcidRecordEntity>(entityName: "UricAcidRecordEntity")
                request.sortDescriptors = [NSSortDescriptor(key: "measuredAt", ascending: true)]
                return request
            }(), managedObjectContext: manual.viewContext,
            sectionNameKeyPath: nil, cacheName: nil
        )
        let manualObserver = ResultsObserver()
        manualController.delegate = manualObserver
        try manualController.performFetch()
        _ = try await CSVImportStore.apply(incoming, mode: .append, to: manual)
        precondition(manualController.fetchedObjects?.count == 9)
        _ = try await CSVImportStore.apply(replacement, mode: .replace, to: manual)
        precondition(manualController.fetchedObjects?.count == 2)
        _ = try await CSVImportStore.apply(document([Row(7000, 8.123456789, .mgdL)]), mode: .append, to: manual)
        precondition(manualController.fetchedObjects?.count == 3 && manualObserver.changes >= 3)
        try require(try stored(manual).count == 3)
        print("PASS explicit merge fallback refreshes existing fetched results and permits repeated imports after deletes")
        print("PASS all real-store CSV import regression checks")
    }
}
''',
])

with tempfile.TemporaryDirectory(prefix="uriclog-import-store-") as directory:
    directory = pathlib.Path(directory)
    source = directory / "main.swift"
    source.write_text(swift)
    executable = directory / "import-tests"
    subprocess.run([
        "swiftc", "-parse-as-library", "-module-cache-path", str(directory / "module-cache"),
        str(source), "-o", str(executable),
    ], check=True)
    env = os.environ.copy()
    env["TMPDIR"] = str(directory) + "/"
    subprocess.run([
        str(executable), str(directory), "-com.apple.CoreData.ConcurrencyDebug", "1",
    ], check=True, env=env)
