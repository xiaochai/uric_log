import CoreData
import Foundation

enum CSVImportMode: Sendable {
	case append
	case replace
}

enum CSVImportStore {
	enum ImportError: LocalizedError {
		case empty
		case existingRecords
		case unsavedChanges
		case failedToSave

		var errorDescription: String? {
			switch self {
			case .empty: return L10n.string("CSV_IMPORT_EMPTY")
			case .existingRecords: return L10n.string("CSV_IMPORT_EXISTING_RECORDS")
			case .unsavedChanges: return L10n.string("CSV_IMPORT_UNSAVED_CHANGES")
			case .failedToSave: return L10n.string("CSV_IMPORT_SAVE_ERROR")
			}
		}
	}

	/// Accept only a completely validated document and commit all changes together.
	/// A failed replacement must never leave the existing archive empty.
	static func apply(
		_ document: CSVImportDocument,
		mode: CSVImportMode,
		to container: NSPersistentContainer
	) async throws -> Int {
		guard !document.records.isEmpty else { throw ImportError.empty }
		let pendingDeletedIDs: [NSManagedObjectID] = try await container.viewContext.perform {
			guard container.viewContext.insertedObjects.isEmpty,
				container.viewContext.updatedObjects.isEmpty else { throw ImportError.unsavedChanges }
			return container.viewContext.deletedObjects.map(\.objectID)
		}
		try Task.checkCancellation()

		let context = container.newBackgroundContext()
		context.mergePolicy = NSErrorMergePolicy
		context.undoManager = nil
		let changes: [String: [NSManagedObjectID]] = try await context.perform {
			do {
				// Merging a committed background deletion can leave a deleted object
				// registered in the view context. Only rows still in SQLite represent
				// unsaved user deletions and must prevent an import.
				for start in stride(from: 0, to: pendingDeletedIDs.count, by: 500) {
					let request = NSFetchRequest<UricAcidRecordEntity>(entityName: "UricAcidRecordEntity")
					request.predicate = NSPredicate(
						format: "SELF IN %@", Array(pendingDeletedIDs[start..<min(start + 500, pendingDeletedIDs.count)])
					)
					request.fetchLimit = 1
					if try context.count(for: request) > 0 { throw ImportError.unsavedChanges }
				}
				var deletedIDs: [NSManagedObjectID] = []
				switch mode {
				case .append:
					// Keep each predicate below SQLite's parameter limit for large files.
					let ids = document.records.map(\.id)
					for start in stride(from: 0, to: ids.count, by: 500) {
						let request = NSFetchRequest<UricAcidRecordEntity>(entityName: "UricAcidRecordEntity")
						request.predicate = NSPredicate(format: "id IN %@", Array(ids[start..<min(start + 500, ids.count)]))
						request.fetchLimit = 1
						if try context.count(for: request) > 0 {
							throw ImportError.existingRecords
						}
					}
				case .replace:
					let request = NSFetchRequest<UricAcidRecordEntity>(entityName: "UricAcidRecordEntity")
					request.fetchBatchSize = 500
					request.includesPropertyValues = false
					for record in try context.fetch(request) {
						deletedIDs.append(record.objectID)
						context.delete(record)
					}
				}

				guard let entity = NSEntityDescription.entity(forEntityName: "UricAcidRecordEntity", in: context) else {
					throw ImportError.failedToSave
				}
				var inserted: [UricAcidRecordEntity] = []
				for source in document.records {
					let record = UricAcidRecordEntity(entity: entity, insertInto: context)
					record.id = source.id
					record.measuredAt = source.measuredAt
					record.value = source.value
					record.unit = source.unit
					record.note = source.note
					record.createdAt = source.createdAt
					record.updatedAt = source.updatedAt
					inserted.append(record)
				}
				try context.save()
				return [
					NSInsertedObjectsKey: inserted.map(\.objectID),
					NSDeletedObjectsKey: deletedIDs,
				]
			} catch {
				context.rollback()
				if let importError = error as? ImportError { throw importError }
				throw ImportError.failedToSave
			}
		}

		// Let automatic merging finish before reporting success. Containers without
		// automatic merging receive only the committed object IDs explicitly.
		// This does not save, reset or roll back the interface's context.
		await container.viewContext.perform(schedule: .enqueued) {
			if !container.viewContext.automaticallyMergesChangesFromParent {
				NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [container.viewContext])
			}
			container.viewContext.processPendingChanges()
		}
		return document.records.count
	}
}
