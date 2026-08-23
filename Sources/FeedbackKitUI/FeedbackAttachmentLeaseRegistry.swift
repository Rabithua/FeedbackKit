import FeedbackKitCore
import Foundation

struct FeedbackAttachmentLeaseRegistry {
    private var leases: [UUID: FeedbackTemporaryFileLease] = [:]

    mutating func retain(
        _ lease: FeedbackTemporaryFileLease,
        for source: FeedbackAttachmentSource
    ) -> Bool {
        guard source.fileURL == lease.url else { return false }
        leases[source.id] = lease
        return true
    }

    mutating func release(id: UUID) {
        leases[id] = nil
    }

    mutating func retainOnly(ids: Set<UUID>) {
        leases = leases.filter { ids.contains($0.key) }
    }

    mutating func removeAll() {
        leases.removeAll()
    }
}
