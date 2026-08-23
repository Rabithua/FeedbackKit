import FeedbackKitCore
import UniformTypeIdentifiers

struct FeedbackAttachmentImportPolicy {
    let limits: FeedbackAttachmentLimits

    func remainingCount(after currentCount: Int) -> Int {
        max(0, limits.count - currentCount)
    }

    func supportedType(in contentTypes: [UTType]) -> UTType? {
        contentTypes.first { Self.allowedTypeIdentifiers.contains($0.identifier) }
    }

    func byteLimit(forMIMEType mimeType: String) -> Int {
        mimeType.hasPrefix("video/") ? limits.videoBytes : limits.imageBytes
    }

    private static let allowedTypeIdentifiers: Set<String> = [
        "public.jpeg",
        "public.png",
        "public.heic",
        "org.webmproject.webp",
        "com.compuserve.gif",
        "public.mpeg-4",
        "com.apple.quicktime-movie",
    ]
}
