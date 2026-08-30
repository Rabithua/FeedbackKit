import Foundation

extension FeedbackClient {
    private static let serviceRestrictionCodes: Set<String> = [
        "feedback_feature_unavailable",
        "feedback_service_read_only",
        "feedback_storage_unavailable",
    ]

    public func uploadDiagnosticSnapshot(_ snapshot: FeedbackDiagnosticSnapshot) async throws -> String {
        let presigned = try await send(
            DiagnosticPresignResponse.self,
            operation: .diagnosticPresign,
            method: .post,
            path: "diagnostics/presign",
            body: DiagnosticPresignRequest(
                filename: "diagnostics.json",
                contentType: "application/json",
                size: snapshot.data.count,
                sha256: snapshot.sha256,
                schemaVersion: snapshot.schemaVersion
            )
        )
        do {
            try await upload(
                snapshot.data,
                to: presigned.uploadUrl,
                headers: presigned.headers,
                operation: .diagnosticUpload
            )
            let finalized = try await send(
                DiagnosticFinalizeResponse.self,
                operation: .diagnosticFinalize,
                method: .post,
                path: "diagnostics/finalize",
                body: DiagnosticFinalizeRequest(diagnosticArtifactId: presigned.diagnosticArtifactId)
            )
            return finalized.id
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
            }
            if let clientError = error as? FeedbackClientError,
               clientError.kind == .server,
               clientError.context.statusCode == 503,
               let code = clientError.context.serverCode,
               Self.serviceRestrictionCodes.contains(code) {
                throw clientError
            }
            if let clientError = error as? FeedbackClientError {
                throw FeedbackClientError(
                    kind: .diagnosticUploadFailed,
                    context: clientError.context
                )
            }
            throw FeedbackClientError(
                kind: .diagnosticUploadFailed,
                context: FeedbackFailureContext(
                    operation: .diagnosticUpload,
                    debugDescription: safeDebugDescription(for: error)
                )
            )
        }
    }

    func diagnosticsReadiness(
        for capability: FeedbackDiagnosticsCapability?
    ) -> FeedbackDiagnosticsReadiness {
        guard let capability, capability.enabled else { return .disabled }
        guard capability.schemaVersions.contains(1) else {
            return .unsupportedSchema(capability.schemaVersions)
        }
        guard diagnostics != nil else {
            return .providerMissing(maxBytes: capability.maxBytes)
        }
        return .ready(maxBytes: capability.maxBytes)
    }
}

struct DiagnosticPresignRequest: Encodable, Sendable { let filename: String; let contentType: String; let size: Int; let sha256: String; let schemaVersion: Int }
struct DiagnosticPresignResponse: Decodable, Sendable { let diagnosticArtifactId: String; let uploadUrl: URL; let headers: RequiredHeaders; let expiresIn: Int }
struct DiagnosticFinalizeRequest: Encodable, Sendable { let diagnosticArtifactId: String }
struct DiagnosticFinalizeResponse: Decodable, Sendable { let id: String }
