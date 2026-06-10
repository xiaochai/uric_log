import Foundation
import CoreData

@objc(UricAcidRecordEntity)
final class UricAcidRecordEntity: NSManagedObject {
	@NSManaged var id: UUID
	@NSManaged var measuredAt: Date
	@NSManaged var value: Double
	@NSManaged var unitRawValue: String
	@NSManaged var note: String?
	@NSManaged var createdAt: Date
	@NSManaged var updatedAt: Date

	var unit: UricUnit {
		get { UricUnit(rawValue: unitRawValue) ?? .umolL }
		set { unitRawValue = newValue.rawValue }
	}

	static func create(
		in context: NSManagedObjectContext,
		measuredAt: Date,
		value: Double,
		unit: UricUnit,
		note: String?
	) -> UricAcidRecordEntity {
		let record = UricAcidRecordEntity(context: context)
		record.id = UUID()
		record.measuredAt = measuredAt
		record.value = value
		record.unit = unit
		record.note = note
		let now = Date()
		record.createdAt = now
		record.updatedAt = now
		return record
	}
}
