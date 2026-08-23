import CoreTransferable
import UniformTypeIdentifiers

struct FeedbackImportedAttachmentFile: Transferable {
    let lease: FeedbackTemporaryFileLease

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            Self(lease: try FeedbackTemporaryFileLease(copying: received.file))
        }
        FileRepresentation(importedContentType: .movie) { received in
            Self(lease: try FeedbackTemporaryFileLease(copying: received.file))
        }
    }
}
