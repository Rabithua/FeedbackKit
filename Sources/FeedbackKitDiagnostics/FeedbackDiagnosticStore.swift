import Foundation

actor FeedbackDiagnosticStore {
    private let configuration: FeedbackDiagnosticsConfiguration
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(configuration: FeedbackDiagnosticsConfiguration) {
        self.configuration = configuration
        if let configured = configuration.directory {
            directory = configured
        } else {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            directory = root.appending(path: "FeedbackKit/Diagnostics", directoryHint: .isDirectory)
        }
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func append(event: FeedbackDiagnosticEvent) throws {
        try append(StoredDiagnosticRecord(kind: .event, timestamp: event.timestamp, event: event, breadcrumb: nil))
    }

    func append(breadcrumb: FeedbackBreadcrumb) throws {
        try append(StoredDiagnosticRecord(kind: .breadcrumb, timestamp: breadcrumb.timestamp, event: nil, breadcrumb: breadcrumb))
    }

    func records() throws -> [StoredDiagnosticRecord] {
        try segmentURLs().flatMap { url in
            let data = try Data(contentsOf: url)
            return data.split(separator: 0x0A).compactMap { line in
                try? decoder.decode(StoredDiagnosticRecord.self, from: Data(line))
            }
        }.sorted { $0.timestamp < $1.timestamp }
    }

    func exportText() throws -> String {
        try records().compactMap { record in
            if let event = record.event {
                return "\(event.timestamp.formatted(.iso8601)) [\(event.level.rawValue.uppercased())] [\(event.category)] \(event.message)"
            }
            if let breadcrumb = record.breadcrumb {
                return "\(breadcrumb.timestamp.formatted(.iso8601)) [\(breadcrumb.kind.rawValue.uppercased())] \(breadcrumb.name)"
            }
            return nil
        }.joined(separator: "\n")
    }

    func clear() throws {
        for url in try segmentURLs() { try FileManager.default.removeItem(at: url) }
    }

    private func append(_ record: StoredDiagnosticRecord) throws {
        try prepareDirectory()
        let url = segmentURL(record.timestamp)
        var line = try encoder.encode(record)
        line.append(0x0A)
        if FileManager.default.fileExists(atPath: url.path) == false {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
            ])
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try prune(now: record.timestamp)
    }

    private func prune(now: Date) throws {
        let cutoff = now.addingTimeInterval(-TimeInterval(configuration.retentionDays * 86_400))
        var retained = try records().filter { $0.timestamp >= cutoff }
        if retained.count > configuration.maximumEventCount {
            retained.removeFirst(retained.count - configuration.maximumEventCount)
        }
        while encodedSize(retained) > configuration.maximumDiskBytes, retained.isEmpty == false {
            retained.removeFirst()
        }
        let existing = try segmentURLs()
        let originalCount = try existing.reduce(0) { $0 + (try Data(contentsOf: $1).split(separator: 0x0A).count) }
        guard retained.count != originalCount || existing.reduce(0, { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }) > configuration.maximumDiskBytes else { return }
        for url in existing { try FileManager.default.removeItem(at: url) }
        let groups = Dictionary(grouping: retained, by: { segmentName($0.timestamp) })
        for (name, records) in groups {
            let data = try records.reduce(into: Data()) { result, record in
                result.append(try encoder.encode(record)); result.append(0x0A)
            }
            let url = directory.appending(path: name)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private func encodedSize(_ records: [StoredDiagnosticRecord]) -> Int {
        records.reduce(0) { $0 + ((try? encoder.encode($1).count) ?? 0) + 1 }
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
        ])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var mutable = directory; try? mutable.setResourceValues(values)
    }

    private func segmentURLs() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func segmentURL(_ date: Date) -> URL { directory.appending(path: segmentName(date)) }
    private func segmentName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHH"
        return "events-\(formatter.string(from: date)).jsonl"
    }
}
