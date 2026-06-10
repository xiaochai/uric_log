import Foundation
import CoreData

enum Persistence {
	static func buildContainer(iCloudEnabled: Bool) -> NSPersistentContainer {
		let model = makeManagedObjectModel()
		let container: NSPersistentContainer
		if iCloudEnabled {
			container = NSPersistentCloudKitContainer(name: "UricLog", managedObjectModel: model)
		} else {
			container = NSPersistentContainer(name: "UricLog", managedObjectModel: model)
		}

		let storeURL = makeStoreURL()
		let description = NSPersistentStoreDescription(url: storeURL)
		description.type = NSSQLiteStoreType
		description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
		description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
		if iCloudEnabled {
			description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.tech.xiaochai.uriclog")
		}
		container.persistentStoreDescriptions = [description]
		return container
	}

	private static func makeStoreURL() -> URL {
		let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
		let dir = base.appendingPathComponent("UricLog", isDirectory: true)
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir.appendingPathComponent("UricLog.sqlite")
	}

	private static func makeManagedObjectModel() -> NSManagedObjectModel {
		let model = NSManagedObjectModel()
		let entity = NSEntityDescription()
		entity.name = "UricAcidRecordEntity"
		entity.managedObjectClassName = NSStringFromClass(UricAcidRecordEntity.self)

		let id = NSAttributeDescription()
		id.name = "id"
		id.attributeType = .UUIDAttributeType
		id.isOptional = false
		id.defaultValue = UUID()

		let measuredAt = NSAttributeDescription()
		measuredAt.name = "measuredAt"
		measuredAt.attributeType = .dateAttributeType
		measuredAt.isOptional = false
		measuredAt.defaultValue = Date(timeIntervalSince1970: 0)

		let value = NSAttributeDescription()
		value.name = "value"
		value.attributeType = .doubleAttributeType
		value.isOptional = false
		value.defaultValue = 0.0

		let unitRawValue = NSAttributeDescription()
		unitRawValue.name = "unitRawValue"
		unitRawValue.attributeType = .stringAttributeType
		unitRawValue.isOptional = false
		unitRawValue.defaultValue = UricUnit.umolL.rawValue

		let note = NSAttributeDescription()
		note.name = "note"
		note.attributeType = .stringAttributeType
		note.isOptional = true

		let createdAt = NSAttributeDescription()
		createdAt.name = "createdAt"
		createdAt.attributeType = .dateAttributeType
		createdAt.isOptional = false
		createdAt.defaultValue = Date(timeIntervalSince1970: 0)

		let updatedAt = NSAttributeDescription()
		updatedAt.name = "updatedAt"
		updatedAt.attributeType = .dateAttributeType
		updatedAt.isOptional = false
		updatedAt.defaultValue = Date(timeIntervalSince1970: 0)

		entity.properties = [id, measuredAt, value, unitRawValue, note, createdAt, updatedAt]
		model.entities = [entity]
		return model
	}
}
