@testable import FeedbackKitCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing

private extension Tag {
    @Tag static var attachmentNetworking: Self
}

private actor AttachmentCredential: FeedbackVisitorCredentialProviding {
    func credential(for productKey: String) async throws -> String {
        "visitor-credential"
    }

    func deleteCredential(for productKey: String) async throws {}
}

private actor AttachmentUploadTransport: FeedbackTransport {
    private(set) var dataUploadCount = 0
    private(set) var fileUploadCount = 0
    private(set) var uploadedFileURL: URL?
    private(set) var presignBody: Data?

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        switch (request.httpMethod, request.url?.path) {
        case ("POST", "/v1/api/client/uploads/presign"):
            presignBody = request.httpBody
            let data = Data(
                #"{"code":"ok","message":"OK","data":[{"attachmentId":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","uploadUrl":"https://storage.example/attachment","headers":{"Content-Type":"image/png","Content-Length":"5"},"expiresIn":900}]}"#.utf8
            )
            return try response(for: request, data: data)
        case ("POST", "/v1/api/client/uploads/finalize"):
            let data = Data(
                #"{"code":"ok","message":"OK","data":[{"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}]}"#.utf8
            )
            return try response(for: request, data: data)
        default:
            throw URLError(.unsupportedURL)
        }
    }

    func upload(for request: URLRequest, data: Data) async throws -> HTTPURLResponse {
        dataUploadCount += 1
        return try response(for: request, data: Data()).1
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> HTTPURLResponse {
        fileUploadCount += 1
        uploadedFileURL = fileURL
        return try response(for: request, data: Data()).1
    }

    private func response(
        for request: URLRequest,
        statusCode: Int = 200,
        data: Data
    ) throws -> (Data, HTTPURLResponse) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: [:]
              )
        else { throw URLError(.badServerResponse) }
        return (data, response)
    }
}

struct FeedbackAttachmentUploadTests {
    @Test("File-backed attachment uses the file upload transport", .tags(.attachmentNetworking))
    func fileBackedAttachmentStreamsFromFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "FeedbackAttachmentUploadTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "attachment.png")
        try Data("image".utf8).write(to: fileURL)
        let source = try FeedbackAttachmentSource(
            filename: "attachment.png",
            contentType: "image/png",
            fileURL: fileURL
        )
        let transport = AttachmentUploadTransport()
        let client = makeClient(transport: transport)

        let ids = try await client.uploadAttachments([source])

        #expect(ids == ["bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"])
        #expect(source.byteCount == 5)
        #expect(source.fileURL == fileURL.standardizedFileURL)
        #expect(try source.loadData() == Data("image".utf8))
        #expect(await transport.fileUploadCount == 1)
        #expect(await transport.dataUploadCount == 0)
        #expect(await transport.uploadedFileURL == fileURL.standardizedFileURL)
        let declaration = try presignDeclaration(await transport.presignBody)
        #expect(declaration["size"] as? Int == 5)
    }

    @Test("Data-backed attachment keeps the existing upload path", .tags(.attachmentNetworking))
    func dataBackedAttachmentUsesDataTransport() async throws {
        let events = Mutex<[FeedbackClientEvent]>([])
        let source = FeedbackAttachmentSource(
            filename: "attachment.png",
            contentType: "image/png",
            data: Data("image".utf8)
        )
        let transport = AttachmentUploadTransport()
        let client = makeClient(
            observer: FeedbackClientObserver { event in
                events.withLock { $0.append(event) }
            },
            transport: transport
        )

        _ = try await client.uploadAttachments([source])

        #expect(source.byteCount == 5)
        #expect(source.fileURL == nil)
        #expect(await transport.dataUploadCount == 1)
        #expect(await transport.fileUploadCount == 0)
        #expect(events.withLock { $0.map(\.operation) } == [
            .attachmentPresign,
            .attachmentUpload,
            .attachmentFinalize,
        ])
        #expect(events.withLock { $0.allSatisfy { $0.outcome == .succeeded } })
    }

    private func makeClient(
        observer: FeedbackClientObserver? = nil,
        transport: AttachmentUploadTransport
    ) -> FeedbackClient {
        FeedbackClient(
            configuration: try! FeedbackConfiguration(
                productKey: "pk_test",
                keychainService: "test.feedback.visitor"
            ),
            observer: observer,
            transport: transport,
            credentialStore: AttachmentCredential()
        )
    }

    private func presignDeclaration(_ data: Data?) throws -> [String: Any] {
        let data = try #require(data)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let files = try #require(object["files"] as? [[String: Any]])
        return try #require(files.first)
    }
}
