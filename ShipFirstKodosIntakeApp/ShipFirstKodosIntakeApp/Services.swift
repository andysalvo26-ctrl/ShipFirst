import Foundation
import SwiftUI

struct RuntimeConfig {
    let supabaseURL: URL
    let supabaseAnonKey: String

    static func fromBundle() throws -> RuntimeConfig {
        guard let urlString = infoValue("SHIPFIRST_SUPABASE_URL"),
              let url = URL(string: urlString),
              url.scheme?.isEmpty == false,
              url.host?.isEmpty == false else {
            throw AppError.missingConfiguration("Missing SHIPFIRST_SUPABASE_URL in app configuration.")
        }

        guard let anonKey = infoValue("SHIPFIRST_SUPABASE_ANON_KEY") else {
            throw AppError.missingConfiguration("Missing SHIPFIRST_SUPABASE_ANON_KEY in app configuration.")
        }

        return RuntimeConfig(supabaseURL: url, supabaseAnonKey: anonKey)
    }

    static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func redacted(_ value: String) -> String {
        let count = value.count
        if count <= 8 { return String(repeating: "*", count: max(4, count)) }
        let prefix = value.prefix(4)
        let suffix = value.suffix(4)
        return "\(prefix)••••\(suffix)"
    }
}

enum AppError: LocalizedError {
    case missingConfiguration(String)
    case network(String)
    case unauthorized
    case forbidden(String)
    case validation(String, [String])
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let message): return message
        case .network(let message): return message
        case .unauthorized: return "Your session is not authorized. Please sign in again."
        case .forbidden(let message): return message
        case .validation(let message, let issues):
            if issues.isEmpty { return message }
            return ([message] + issues.map { "• \($0)" }).joined(separator: "\n")
        case .malformedResponse(let message): return message
        }
    }
}

enum SessionInspector {
    private static func decodedPayload(accessToken: String) -> [String: Any]? {
        let token = normalizedAccessToken(accessToken)
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = payload.count % 4
        if padding > 0 {
            payload += String(repeating: "=", count: 4 - padding)
        }

        guard let payloadData = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func numericTimestamp(for value: Any?) -> TimeInterval? {
        guard let value else { return nil }
        if let intValue = value as? Int {
            return TimeInterval(intValue)
        }
        if let doubleValue = value as? Double {
            return doubleValue
        }
        if let numberValue = value as? NSNumber {
            return numberValue.doubleValue
        }
        return nil
    }

    static func normalizedAccessToken(_ token: String) -> String {
        var trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("bearer ") {
            trimmed = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    static func jwtIssueAndExpiry(accessToken: String) -> (issuedAt: String?, expiresAt: String?) {
        guard let json = decodedPayload(accessToken: accessToken) else {
            return (nil, nil)
        }

        func isoString(for value: Any?) -> String? {
            let timestamp = numericTimestamp(for: value)
            guard let timestamp else { return nil }
            return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
        }

        return (
            issuedAt: isoString(for: json["iat"]),
            expiresAt: isoString(for: json["exp"])
        )
    }

    static func expiryDate(accessToken: String) -> Date? {
        guard let json = decodedPayload(accessToken: accessToken),
              let exp = numericTimestamp(for: json["exp"]) else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }

    static func isExpiringSoon(accessToken: String, within seconds: TimeInterval) -> Bool {
        guard let expiry = expiryDate(accessToken: accessToken) else { return false }
        return expiry.timeIntervalSinceNow <= seconds
    }

    static func redactedToken(_ token: String?) -> String {
        guard let token, !token.isEmpty else { return "none" }
        if token.count <= 8 {
            return String(repeating: "*", count: token.count)
        }
        return "\(token.prefix(4))••••\(token.suffix(4))"
    }
}

private enum APIDiagnostics {
    struct EdgeIssue: Decodable {
        let code: String?
        let message: String?
        let decisionKey: String?

        enum CodingKeys: String, CodingKey {
            case code
            case message
            case decisionKey = "decision_key"
        }
    }

    struct EdgeErrorPayload: Decodable {
        let code: String?
        let message: String?
        let layer: String?
        let operation: String?
        let issues: [EdgeIssue]?
    }

    struct EdgeErrorEnvelope: Decodable {
        let error: EdgeErrorPayload
    }

    enum RequestLayer: String {
        case auth = "auth"
        case postgrest = "postgrest"
        case edgeFunction = "edge_function"
        case http = "http"

        static func from(url: URL) -> RequestLayer {
            let path = url.path
            if path.contains("/auth/v1/") { return .auth }
            if path.contains("/rest/v1/") { return .postgrest }
            if path.contains("/functions/v1/") { return .edgeFunction }
            return .http
        }
    }

    static func log(_ message: String) {
#if DEBUG
        print("[ShipFirstAPI] \(message)")
#endif
    }

    static func summarizeResponseBody(_ data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let nested = json["error"] as? [String: Any] {
                var nestedSegments: [String] = []
                for key in ["code", "message", "layer", "details", "hint", "operation"] {
                    if let value = nested[key], !String(describing: value).isEmpty {
                        nestedSegments.append("\(key)=\(value)")
                    }
                }
                if !nestedSegments.isEmpty {
                    return nestedSegments.joined(separator: " | ")
                }
            }

            var segments: [String] = []
            for key in ["code", "message", "details", "hint", "error", "error_description"] {
                if let value = json[key], !String(describing: value).isEmpty {
                    segments.append("\(key)=\(value)")
                }
            }
            if !segments.isEmpty {
                return segments.joined(separator: " | ")
            }
        }

        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty { return "<empty>" }
        return raw.count > 400 ? "\(raw.prefix(400))…" : raw
    }

    static func decodeEdgeError(_ data: Data) -> EdgeErrorEnvelope? {
        try? JSONDecoder().decode(EdgeErrorEnvelope.self, from: data)
    }
}

private enum SessionStore {
    static let key = "shipfirst.auth.session"
    static let scopeKey = "shipfirst.auth.session.scope"

    static func load(for config: RuntimeConfig) -> AuthSession? {
        let expectedScope = scopeSignature(for: config)
        let currentScope = UserDefaults.standard.string(forKey: scopeKey)
        if currentScope != expectedScope {
            clear()
            UserDefaults.standard.set(expectedScope, forKey: scopeKey)
            return nil
        }
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    static func save(_ session: AuthSession?, for config: RuntimeConfig) {
        UserDefaults.standard.set(scopeSignature(for: config), forKey: scopeKey)
        if let session {
            let data = try? JSONEncoder().encode(session)
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: scopeKey)
    }

    private static func scopeSignature(for config: RuntimeConfig) -> String {
        let host = config.supabaseURL.host ?? config.supabaseURL.absoluteString
        let keyPrefix = String(config.supabaseAnonKey.prefix(16))
        return "\(host)|\(keyPrefix)"
    }
}

enum IntakeTurnPayloadBuilder {
    static func payload(
        projectID: UUID,
        cycleNo: Int,
        text: String,
        turnIndex: Int,
        actor: IntakeActor,
        includeActorType: Bool = true,
        includeLegacyActor: Bool = false
    ) -> [String: Any] {
        precondition(includeActorType || includeLegacyActor, "At least one actor field must be included.")
        precondition(turnIndex >= 1, "turn_index must be >= 1.")

        var payload: [String: Any] = [
            "project_id": projectID.uuidString,
            "cycle_no": cycleNo,
            "turn_index": turnIndex,
            "raw_text": text
        ]
        if includeActorType {
            payload["actor_type"] = actor.rawValue
        }
        if includeLegacyActor {
            payload["actor"] = actor.rawValue
        }
        return payload
    }

    static func hasRequiredActorAndProject(_ payload: [String: Any]) -> Bool {
        guard let projectID = payload["project_id"] as? String, !projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let actorValue = (payload["actor_type"] as? String) ?? (payload["actor"] as? String)
        guard let actorValue, !actorValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return IntakeActor(rawValue: actorValue) != nil
    }

    static func debugJSON(_ payload: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "<invalid-json>"
        }
        return json
    }
}

@MainActor
final class DraftStore: ObservableObject {
    @Published var currentDraftText: String = ""
    @Published var localAlignmentAnswers: [String: String] = [:]

    func resetBlankCanvas() {
        currentDraftText = ""
        localAlignmentAnswers = [:]
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var session: AuthSession?
    @Published var configError: String?
    @Published var isReady: Bool = false

    let draftStore = DraftStore()
    private let sessionReference = SessionReference()
    private let runtimeConfig: RuntimeConfig?
    let api: SupabaseAPI?

    init() {
        do {
            let config = try RuntimeConfig.fromBundle()
            self.runtimeConfig = config
            print("ShipFirst config loaded: url=\(config.supabaseURL.absoluteString), anon=\(RuntimeConfig.redacted(config.supabaseAnonKey))")
            let loadedSession = SessionStore.load(for: config)
            if let loadedSession {
                let claims = SessionInspector.jwtIssueAndExpiry(accessToken: loadedSession.accessToken)
                APIDiagnostics.log("session.restore user=\(loadedSession.userID.uuidString) issued_at=\(claims.issuedAt ?? "unknown") expires_at=\(claims.expiresAt ?? "unknown") token=\(SessionInspector.redactedToken(loadedSession.accessToken))")
            } else {
                APIDiagnostics.log("session.restore no local session")
            }
            self.session = loadedSession
            self.sessionReference.value = loadedSession
            let ref = self.sessionReference
            let api = SupabaseAPI(
                config: config,
                sessionProvider: { ref.value },
                sessionWriter: { newSession in
                    ref.value = newSession
                    SessionStore.save(newSession, for: config)
                }
            )
            self.api = api
            api.onSessionInvalid = { [weak self] in
                Task { @MainActor in
                    self?.signOut()
                }
            }
            self.isReady = true
        } catch {
            self.runtimeConfig = nil
            self.api = nil
            self.configError = error.localizedDescription
            self.isReady = false
        }
    }

    func saveSession(_ session: AuthSession?) {
        self.session = session
        self.sessionReference.value = session
        if let runtimeConfig {
            SessionStore.save(session, for: runtimeConfig)
        }
    }

    func signOut() {
        saveSession(nil)
        draftStore.resetBlankCanvas()
    }
}

final class SessionReference {
    var value: AuthSession?
}

private struct ProjectRow: Decodable {
    let id: UUID
    let ownerUserID: UUID?
    let name: String?
    let activeCycleNo: Int?
    let createdAt: String
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserID = "owner_user_id"
        case name
        case activeCycleNo = "active_cycle_no"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct ProjectCycleRow: Decodable {
    let id: UUID?
    let activeCycleNo: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case activeCycleNo = "active_cycle_no"
    }
}

private struct ContractVersionListRow: Decodable {
    let id: UUID
    let projectID: UUID
    let cycleNo: Int
    let versionNumber: Int?
    let status: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case cycleNo = "cycle_no"
        case versionNumber = "version_number"
        case status
        case createdAt = "created_at"
    }
}

private struct SubmissionArtifactRow: Decodable {
    let id: UUID
    let contractVersionID: UUID
    let storagePath: String
    let submittedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case contractVersionID = "contract_version_id"
        case storagePath = "storage_path"
        case submittedAt = "submitted_at"
    }
}

final class SupabaseAPI {
    private enum IntakeInsertRetryMode {
        case includeLegacyActorAndCanonical
        case legacyActorOnly
    }

    private let config: RuntimeConfig
    private let sessionProvider: () -> AuthSession?
    private let sessionWriter: (AuthSession?) -> Void
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    var onSessionInvalid: (() -> Void)?

    init(
        config: RuntimeConfig,
        sessionProvider: @escaping () -> AuthSession?,
        sessionWriter: @escaping (AuthSession?) -> Void
    ) {
        self.config = config
        self.sessionProvider = sessionProvider
        self.sessionWriter = sessionWriter
    }

    // MARK: Auth
    func signUp(email: String, password: String) async throws -> AuthSession {
        let endpoint = config.supabaseURL.appendingPathComponent("auth/v1/signup")
        let body: [String: String] = ["email": email, "password": password]
        let response: AuthResponse = try await request(
            url: endpoint,
            method: "POST",
            bearerToken: nil,
            body: body,
            requiresAuth: false
        )
        return try buildSession(from: response, fallbackEmail: email)
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        var components = URLComponents(url: config.supabaseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
        guard let endpoint = components?.url else {
            throw AppError.malformedResponse("Could not build sign-in URL.")
        }

        let body: [String: String] = ["email": email, "password": password]
        let response: AuthResponse = try await request(
            url: endpoint,
            method: "POST",
            bearerToken: nil,
            body: body,
            requiresAuth: false
        )
        return try buildSession(from: response, fallbackEmail: email)
    }

    private func buildSession(from response: AuthResponse, fallbackEmail: String? = nil) throws -> AuthSession {
        guard let accessToken = response.accessToken,
              let refreshToken = response.refreshToken,
              let user = response.user else {
            throw AppError.malformedResponse(response.errorDescription ?? response.msg ?? "Auth response missing session fields.")
        }

        let resolvedEmail = user.email ?? fallbackEmail
        guard let resolvedEmail, !resolvedEmail.isEmpty else {
            throw AppError.malformedResponse("Auth response did not include a usable email.")
        }

        return AuthSession(accessToken: accessToken, refreshToken: refreshToken, userID: user.id, email: resolvedEmail)
    }

    private func refreshSession() async throws -> AuthSession {
        guard let current = sessionProvider() else {
            throw AppError.unauthorized
        }

        var components = URLComponents(url: config.supabaseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        guard let endpoint = components?.url else {
            throw AppError.malformedResponse("Could not build token refresh URL.")
        }

        do {
            let response: AuthResponse = try await request(
                url: endpoint,
                method: "POST",
                bearerToken: nil,
                body: ["refresh_token": current.refreshToken],
                requiresAuth: false,
                retryOnUnauthorized: false
            )

            guard let accessToken = response.accessToken,
                  let refreshToken = response.refreshToken else {
                throw AppError.unauthorized
            }

            let refreshed = AuthSession(
                accessToken: accessToken,
                refreshToken: refreshToken,
                userID: response.user?.id ?? current.userID,
                email: response.user?.email ?? current.email
            )
            sessionWriter(refreshed)
            return refreshed
        } catch let error as AppError {
            switch error {
            case .unauthorized, .forbidden:
                sessionWriter(nil)
                onSessionInvalid?()
                throw AppError.unauthorized
            default:
                throw error
            }
        } catch {
            throw error
        }
    }

    // MARK: Plans (mapped to project + cycle revision)
    func listRuns() async throws -> [RunSummary] {
        let projectURL = try postgrestURL(path: "projects", query: "select=id,owner_user_id,name,active_cycle_no,created_at,updated_at&order=created_at.desc")
        let projects: [ProjectRow] = try await request(
            url: projectURL,
            method: "GET",
            bearerToken: requiredSession().accessToken,
            operation: "runs.list.projects"
        )

        let versionsURL = try postgrestURL(path: "contract_versions", query: "select=id,project_id,cycle_no,version_number,status,created_at&order=created_at.desc")
        let versions: [ContractVersionListRow]
        do {
            versions = try await request(
                url: versionsURL,
                method: "GET",
                bearerToken: requiredSession().accessToken,
                operation: "runs.list.contract_versions"
            )
        } catch let appError as AppError {
            if case .forbidden(let detail) = appError {
                APIDiagnostics.log("runs.list.contract_versions denied; continuing with empty versions. \(detail)")
                versions = []
            } else {
                throw appError
            }
        }

        let submissionsURL = try postgrestURL(path: "submission_artifacts", query: "select=id,contract_version_id,storage_path,submitted_at&order=submitted_at.desc")
        let submissions: [SubmissionArtifactRow]
        do {
            submissions = try await request(
                url: submissionsURL,
                method: "GET",
                bearerToken: requiredSession().accessToken,
                operation: "runs.list.submission_artifacts"
            )
        } catch let appError as AppError {
            switch appError {
            case .forbidden(let detail):
                APIDiagnostics.log("runs.list.submission_artifacts denied; continuing with empty submissions. \(detail)")
                submissions = []
            case .network(let message) where message.contains("PGRST205") || message.contains("submission_artifacts"):
                APIDiagnostics.log("runs.list.submission_artifacts unavailable; continuing with empty submissions. \(message)")
                submissions = []
            default:
                throw appError
            }
        }
        let submissionByVersion = Dictionary(uniqueKeysWithValues: submissions.map { ($0.contractVersionID, $0) })

        var latestByProjectCycle: [String: ContractVersionListRow] = [:]
        for row in versions {
            let key = "\(row.projectID.uuidString):\(row.cycleNo)"
            if latestByProjectCycle[key] == nil {
                latestByProjectCycle[key] = row
            }
        }

        var output: [RunSummary] = []
        for project in projects {
            let matching = latestByProjectCycle.values.filter { $0.projectID == project.id }
            if matching.isEmpty {
                output.append(
                    RunSummary(
                        projectID: project.id,
                        cycleNo: max(project.activeCycleNo ?? 1, 1),
                        title: project.name ?? "Untitled Project",
                        status: "draft",
                        latestContractVersionID: nil,
                        latestSubmissionPath: nil,
                        createdAt: project.createdAt,
                        updatedAt: project.updatedAt ?? project.createdAt,
                        submittedAt: nil
                    )
                )
            } else {
                for row in matching.sorted(by: { $0.cycleNo > $1.cycleNo }) {
                    let submission = submissionByVersion[row.id]
                    let status = submission == nil ? (row.status ?? "committed") : "submitted"
                    output.append(
                        RunSummary(
                            projectID: row.projectID,
                            cycleNo: row.cycleNo,
                            title: project.name ?? "Untitled Project",
                            status: status,
                            latestContractVersionID: row.id,
                            latestSubmissionPath: submission?.storagePath,
                            createdAt: row.createdAt,
                            updatedAt: row.createdAt,
                            submittedAt: submission?.submittedAt
                        )
                    )
                }
            }
        }

        return output.sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    func createRun() async throws -> RunSummary {
        let name = "Project \(ISO8601DateFormatter().string(from: Date()))"
        let payload: [String: Any] = ["name": name]
        let url = try postgrestURL(path: "projects", query: "select=id,owner_user_id,name,active_cycle_no,created_at,updated_at")
        let created: [ProjectRow] = try await request(
            url: url,
            method: "POST",
            bearerToken: requiredSession().accessToken,
            bodyAny: payload,
            extraHeaders: ["Prefer": "return=representation"]
        )

        guard let project = created.first else {
            throw AppError.malformedResponse("Project creation returned no row.")
        }

        return RunSummary(
            projectID: project.id,
            cycleNo: max(project.activeCycleNo ?? 1, 1),
            title: project.name ?? "Untitled Project",
            status: "draft",
            latestContractVersionID: nil,
            latestSubmissionPath: nil,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt ?? project.createdAt,
            submittedAt: nil
        )
    }

    func startNewCycle(projectID: UUID, from currentCycleNo: Int) async throws -> Int {
        let nextCycle = max(currentCycleNo, 1) + 1

        let updateURL = try postgrestURL(path: "projects", query: "id=eq.\(projectID.uuidString)")
        let payload: [String: Any] = ["active_cycle_no": nextCycle]
        let _: EmptyResponse = try await request(
            url: updateURL,
            method: "PATCH",
            bearerToken: requiredSession().accessToken,
            bodyAny: payload,
            extraHeaders: ["Prefer": "return=minimal"],
            operation: "projects.update_active_cycle"
        )
        return nextCycle
    }

    func listIntakeTurns(projectID: UUID, cycleNo: Int) async throws -> [IntakeTurn] {
        let query = "project_id=eq.\(projectID.uuidString)&cycle_no=eq.\(cycleNo)&select=id,project_id,cycle_no,actor_type,turn_index,raw_text,created_at&order=turn_index.asc"
        let url = try postgrestURL(path: "intake_turns", query: query)
        return try await request(url: url, method: "GET", bearerToken: requiredSession().accessToken)
    }

    func addIntakeTurn(projectID: UUID, cycleNo: Int, text: String, turnIndex: Int) async throws -> IntakeTurn {
        // Provenance integrity: actor must always be explicit for each turn.
        let primaryPayload = IntakeTurnPayloadBuilder.payload(
            projectID: projectID,
            cycleNo: cycleNo,
            text: text,
            turnIndex: turnIndex,
            actor: .user,
            includeActorType: true,
            includeLegacyActor: false
        )
        assert(IntakeTurnPayloadBuilder.hasRequiredActorAndProject(primaryPayload), "intake_turns payload must include project_id and actor")
#if DEBUG
        APIDiagnostics.log("request.payload op=intake_turns.insert payload=\(IntakeTurnPayloadBuilder.debugJSON(primaryPayload))")
#endif
        let url = try postgrestURL(path: "intake_turns", query: "select=id,project_id,cycle_no,turn_index,raw_text,created_at")
        do {
            let inserted: [IntakeTurn] = try await request(
                url: url,
                method: "POST",
                bearerToken: requiredSession().accessToken,
                bodyAny: primaryPayload,
                extraHeaders: ["Prefer": "return=representation"],
                operation: "intake_turns.insert"
            )
            guard let item = inserted.first else {
                throw AppError.malformedResponse("Intake insert returned no row.")
            }
            return item
        } catch {
            if let retryMode = intakeTurnInsertRetryMode(for: error) {
                let includeActorType = retryMode == .includeLegacyActorAndCanonical
                let fallbackPayload = IntakeTurnPayloadBuilder.payload(
                    projectID: projectID,
                    cycleNo: cycleNo,
                    text: text,
                    turnIndex: turnIndex,
                    actor: .user,
                    includeActorType: includeActorType,
                    includeLegacyActor: true
                )
                assert(IntakeTurnPayloadBuilder.hasRequiredActorAndProject(fallbackPayload), "intake_turns fallback payload must include project_id and actor")
#if DEBUG
                APIDiagnostics.log("request.retry op=intake_turns.insert reason=\(retryMode) payload=\(IntakeTurnPayloadBuilder.debugJSON(fallbackPayload))")
#endif
                let inserted: [IntakeTurn] = try await request(
                    url: url,
                    method: "POST",
                    bearerToken: requiredSession().accessToken,
                    bodyAny: fallbackPayload,
                    extraHeaders: ["Prefer": "return=representation"],
                    operation: "intake_turns.insert.legacy_actor_retry"
                )
                guard let item = inserted.first else {
                    throw AppError.malformedResponse("Intake insert retry returned no row.")
                }
                return item
            }
            throw error
        }
    }

    func listDecisionItems(projectID: UUID, cycleNo: Int) async throws -> [DecisionItem] {
        let query = "project_id=eq.\(projectID.uuidString)&cycle_no=eq.\(cycleNo)&select=id,project_id,cycle_no,decision_key,claim,status,evidence_refs,lock_state,confirmed_by_turn_id,has_conflict,conflict_key,updated_at&order=updated_at.desc"
        let url = try postgrestURL(path: "decision_items", query: query)
        return try await request(url: url, method: "GET", bearerToken: requiredSession().accessToken)
    }

    func upsertDecisionItem(projectID: UUID, cycleNo: Int, key: String, claim: String, status: TrustLabel, evidenceRefs: [String], lockState: DecisionLockState) async throws {
        let payload: [String: Any] = [
            "project_id": projectID.uuidString,
            "cycle_no": cycleNo,
            "decision_key": key,
            "claim": claim,
            "status": status.rawValue,
            "evidence_refs": evidenceRefs,
            "lock_state": lockState.rawValue,
        ]
        let url = try postgrestURL(path: "decision_items", query: "on_conflict=project_id,cycle_no,decision_key")
        let _: [DecisionItem] = try await request(
            url: url,
            method: "POST",
            bearerToken: requiredSession().accessToken,
            bodyAny: payload,
            extraHeaders: ["Prefer": "resolution=merge-duplicates,return=representation"]
        )
    }

    func listLatestDocuments(projectID: UUID, cycleNo: Int) async throws -> [BrainDocument] {
        let versionQuery = "project_id=eq.\(projectID.uuidString)&cycle_no=eq.\(cycleNo)&select=id,project_id,cycle_no,version_number,status,created_at&order=version_number.desc&limit=1"
        let versionURL = try postgrestURL(path: "contract_versions", query: versionQuery)
        let versions: [ContractVersionListRow] = try await request(url: versionURL, method: "GET", bearerToken: requiredSession().accessToken)
        guard let latest = versions.first else { return [] }

        let docsQuery = "contract_version_id=eq.\(latest.id.uuidString)&select=id,project_id,cycle_no,contract_version_id,role_id,title,body,is_complete,created_at&order=role_id.asc"
        let docsURL = try postgrestURL(path: "contract_docs", query: docsQuery)
        var docs: [BrainDocument] = try await request(url: docsURL, method: "GET", bearerToken: requiredSession().accessToken)

        let reqQuery = "contract_version_id=eq.\(latest.id.uuidString)&select=id,project_id,cycle_no,contract_version_id,contract_doc_id,role_id,requirement_text,trust_label,requirement_index&order=role_id.asc,requirement_index.asc"
        let reqURL = try postgrestURL(path: "requirements", query: reqQuery)
        let requirements: [RequirementRow] = try await request(url: reqURL, method: "GET", bearerToken: requiredSession().accessToken)

        let provQuery = "contract_version_id=eq.\(latest.id.uuidString)&select=requirement_id,pointer"
        let provURL = try postgrestURL(path: "provenance_links", query: provQuery)
        let provenance: [ProvenancePointerRow] = try await request(url: provURL, method: "GET", bearerToken: requiredSession().accessToken)
        let refsByRequirement = Dictionary(grouping: provenance, by: \.requirementID)

        let claimByDoc = Dictionary(grouping: requirements.map { row in
            DocumentClaim(
                id: row.id,
                projectID: row.projectID,
                cycleNo: row.cycleNo,
                contractVersionID: row.contractVersionID,
                contractDocID: row.contractDocID,
                roleID: row.roleID,
                claimText: row.requirementText,
                trustLabel: row.trustLabel,
                provenanceRefs: refsByRequirement[row.id]?.map(\.pointer) ?? [],
                claimIndex: row.requirementIndex
            )
        }, by: \.contractDocID)

        docs = docs.map { doc in
            var copy = doc
            copy.claims = claimByDoc[doc.id] ?? []
            return copy
        }

        return docs
    }

    func generateDocuments(projectID: UUID, cycleNo: Int, regenerateRoleIDs: [Int]? = nil) async throws -> [BrainDocument] {
        var payload: [String: Any] = ["project_id": projectID.uuidString, "cycle_no": cycleNo]
        if let regenerateRoleIDs { payload["regenerate_role_ids"] = regenerateRoleIDs }

        let response: GenerateDocsResponse = try await authorizedFunctionRequest(
            path: "generate-docs",
            bodyAny: payload,
            operation: "functions.generate_docs"
        )
        return response.documents
    }

    func nextTurn(
        projectID: UUID,
        cycleNo: Int,
        userMessage: String?,
        selectedOptionID: String? = nil,
        noneFitText: String? = nil,
        checkpointResponse: NextTurnCheckpointResponse? = nil,
        artifactRef: String? = nil,
        artifactType: String? = nil,
        forceRefresh: Bool? = nil
    ) async throws -> NextTurnResult {
        let requestModel = NextTurnRequest(
            projectID: projectID,
            cycleNo: cycleNo,
            userMessage: userMessage,
            selectedOptionID: selectedOptionID,
            noneFitText: noneFitText,
            checkpointResponse: checkpointResponse,
            artifactRef: artifactRef,
            artifactType: artifactType,
            forceRefresh: forceRefresh
        )
        guard requestModel.hasActionableInput else {
            throw AppError.validation("Select an option to continue.", ["Provide evidence, choose an option, respond to checkpoint, or provide a website URL."])
        }
        return try await authorizedFunctionRequest(
            path: "next-turn",
            bodyAny: try requestModel.toDictionary(),
            operation: "functions.next_turn"
        )
    }

    func commitContract(projectID: UUID, cycleNo: Int, generationMode: GenerationMode? = nil) async throws -> CommitContractResult {
        let requestModel = CommitContractRequest(projectID: projectID, cycleNo: cycleNo, generationMode: generationMode)
        return try await authorizedFunctionRequest(
            path: "commit-contract",
            bodyAny: try requestModel.toDictionary(),
            operation: "functions.commit_contract"
        )
    }

    func submitRun(projectID: UUID, cycleNo: Int) async throws -> SubmissionResult {
        let payload: [String: Any] = [
            "project_id": projectID.uuidString,
            "cycle_no": cycleNo,
            "review_confirmed": true,
        ]
        return try await authorizedFunctionRequest(
            path: "submit-run",
            bodyAny: payload,
            operation: "functions.submit_run"
        )
    }

    func performTypedAction(projectID: UUID, cycleNo: Int, action: TypedActionKind) async throws -> TypedActionOutcome {
        switch action {
        case .addEvidence(let text):
            let result = try await nextTurn(
                projectID: projectID,
                cycleNo: cycleNo,
                userMessage: text,
                selectedOptionID: nil,
                noneFitText: nil
            )
            return .turn(result)
        case .selectOption(let id, let noneFitText):
            let result = try await nextTurn(
                projectID: projectID,
                cycleNo: cycleNo,
                userMessage: nil,
                selectedOptionID: id,
                noneFitText: noneFitText,
                checkpointResponse: nil
            )
            return .turn(result)
        case .respondCheckpoint(let id, let action, let optionalText):
            let checkpointSelection = "checkpoint:\(action)"
            let result = try await nextTurn(
                projectID: projectID,
                cycleNo: cycleNo,
                userMessage: nil,
                selectedOptionID: checkpointSelection,
                noneFitText: nil,
                checkpointResponse: NextTurnCheckpointResponse(
                    checkpointID: id,
                    action: action,
                    optionalText: optionalText
                )
            )
            return .turn(result)
        case .correctArtifactUnderstanding(let checkpointID, let text):
            if let checkpointID {
                let result = try await nextTurn(
                    projectID: projectID,
                    cycleNo: cycleNo,
                    userMessage: nil,
                    selectedOptionID: "checkpoint:partial",
                    noneFitText: nil,
                    checkpointResponse: NextTurnCheckpointResponse(
                        checkpointID: checkpointID,
                        action: "partial",
                        optionalText: text
                    )
                )
                return .turn(result)
            }
            let result = try await nextTurn(
                projectID: projectID,
                cycleNo: cycleNo,
                userMessage: text,
                selectedOptionID: nil,
                noneFitText: nil
            )
            return .turn(result)
        case .deferUnknown(let pointer, let reason):
            let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message = "Defer unresolved item \(pointer)." + (trimmedReason.isEmpty ? "" : " \(trimmedReason)")
            let result = try await nextTurn(
                projectID: projectID,
                cycleNo: cycleNo,
                userMessage: message,
                selectedOptionID: nil,
                noneFitText: nil
            )
            return .turn(result)
        case .requestCommit(let mode):
            let result = try await commitContract(projectID: projectID, cycleNo: cycleNo, generationMode: mode)
            return .commit(result)
        case .confirmReviewAndSubmit:
            let result = try await submitRun(projectID: projectID, cycleNo: cycleNo)
            return .submit(result)
        }
    }

    private func requiredSession() throws -> AuthSession {
        guard let session = sessionProvider() else {
            throw AppError.unauthorized
        }
        return session
    }

    private func activeAccessTokenForFunctionCall(operation: String) async throws -> String {
        let session = try requiredSession()
        var token = SessionInspector.normalizedAccessToken(session.accessToken)
        guard !token.isEmpty else { throw AppError.unauthorized }

        if SessionInspector.isExpiringSoon(accessToken: token, within: 60) {
            APIDiagnostics.log("function.token.refresh op=\(operation) reason=expiring_soon")
            let refreshed = try await refreshSession()
            token = SessionInspector.normalizedAccessToken(refreshed.accessToken)
            guard !token.isEmpty else { throw AppError.unauthorized }
        }
        return token
    }

    private func authorizedFunctionRequest<T: Decodable>(
        path: String,
        bodyAny: [String: Any],
        operation: String
    ) async throws -> T {
        let endpoint = config.supabaseURL.appendingPathComponent("functions/v1/\(path)")
        let token = try await activeAccessTokenForFunctionCall(operation: operation)
#if DEBUG
        APIDiagnostics.log("function.headers op=\(operation) authorization_present=true bearer_prefix=true token_length=\(token.count) apikey_present=\(!config.supabaseAnonKey.isEmpty)")
#endif
        return try await request(
            url: endpoint,
            method: "POST",
            bearerToken: token,
            bodyAny: bodyAny,
            operation: operation
        )
    }

    private func intakeTurnInsertRetryMode(for error: Error) -> IntakeInsertRetryMode? {
        guard case let AppError.network(message) = error else { return nil }
        let lowered = message.lowercased()
        if lowered.contains("code=23502"),
           lowered.contains("column 'actor'") || lowered.contains("column \"actor\"") {
            return .includeLegacyActorAndCanonical
        }
        if lowered.contains("code=42703"),
           lowered.contains("actor_type"),
           lowered.contains("does not exist") {
            return .legacyActorOnly
        }
        return nil
    }

    private func postgrestURL(path: String, query: String) throws -> URL {
        guard var components = URLComponents(url: config.supabaseURL.appendingPathComponent("rest/v1/\(path)"), resolvingAgainstBaseURL: false) else {
            throw AppError.malformedResponse("Unable to form PostgREST URL.")
        }
        components.percentEncodedQuery = query
        guard let url = components.url else {
            throw AppError.malformedResponse("Unable to form PostgREST URL query.")
        }
        return url
    }

    private func request<T: Decodable>(
        url: URL,
        method: String,
        bearerToken: String?,
        body: [String: String]? = nil,
        bodyAny: [String: Any]? = nil,
        extraHeaders: [String: String] = [:],
        requiresAuth: Bool = true,
        retryOnUnauthorized: Bool = true,
        operation: String? = nil
    ) async throws -> T {
        let op = operation ?? "\(method) \(url.path)"
        let layer = APIDiagnostics.RequestLayer.from(url: url)
        let candidateToken = SessionInspector.normalizedAccessToken(bearerToken ?? sessionProvider()?.accessToken ?? "")
        let claims = SessionInspector.jwtIssueAndExpiry(accessToken: candidateToken)
        APIDiagnostics.log("request.start op=\(op) layer=\(layer.rawValue) path=\(url.path) auth=\(requiresAuth) user=\(sessionProvider()?.userID.uuidString ?? "none") issued_at=\(claims.issuedAt ?? "unknown") expires_at=\(claims.expiresAt ?? "unknown") token=\(SessionInspector.redactedToken(candidateToken))")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")

        if requiresAuth {
            let authToken = SessionInspector.normalizedAccessToken(bearerToken ?? sessionProvider()?.accessToken ?? "")
            guard !authToken.isEmpty else { throw AppError.unauthorized }
            urlRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        for (key, value) in extraHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

#if DEBUG
        let authHeader = urlRequest.value(forHTTPHeaderField: "Authorization") ?? ""
        let hasAuthorization = !authHeader.isEmpty
        let hasBearerPrefix = authHeader.hasPrefix("Bearer ")
        let tokenLength = hasBearerPrefix ? max(0, authHeader.count - "Bearer ".count) : 0
        let hasAPIKey = !(urlRequest.value(forHTTPHeaderField: "apikey") ?? "").isEmpty
        APIDiagnostics.log("request.headers op=\(op) layer=\(layer.rawValue) authorization_present=\(hasAuthorization) bearer_prefix=\(hasBearerPrefix) token_length=\(tokenLength) apikey_present=\(hasAPIKey)")
#endif

        if let body {
            urlRequest.httpBody = try encoder.encode(body)
        } else if let bodyAny {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: bodyAny)
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let http = response as? HTTPURLResponse else {
            throw AppError.network("Invalid HTTP response")
        }

        guard (200...299).contains(http.statusCode) else {
            let payloadSummary = APIDiagnostics.summarizeResponseBody(data)
            let edgeError = APIDiagnostics.decodeEdgeError(data)?.error
            APIDiagnostics.log("request.fail op=\(op) layer=\(layer.rawValue) status=\(http.statusCode) payload=\(payloadSummary)")

            if http.statusCode == 401 || http.statusCode == 403 {
                // Only 401 means token/session auth failure. 403 is an authorization/policy denial
                // and should not force refresh/sign-out.
                if http.statusCode == 401 && requiresAuth && retryOnUnauthorized {
                    let refreshed = try await refreshSession()
                    return try await request(
                        url: url,
                        method: method,
                        bearerToken: refreshed.accessToken,
                        body: body,
                        bodyAny: bodyAny,
                        extraHeaders: extraHeaders,
                        requiresAuth: requiresAuth,
                        retryOnUnauthorized: false,
                        operation: op
                    )
                }
                if http.statusCode == 401 {
                    throw AppError.unauthorized
                }
                if let edgeError {
                    throw AppError.forbidden("Access was denied [\(edgeError.layer ?? layer.rawValue)] for \(op). \(edgeError.message ?? payloadSummary)")
                }
                throw AppError.forbidden("Access was denied [\(layer.rawValue)] for \(op). \(payloadSummary)")
            }

            if edgeError?.layer == "validation" {
                let issues = (edgeError?.issues ?? []).compactMap { $0.message?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                throw AppError.validation(edgeError?.message ?? "Validation failed.", issues)
            }
            throw AppError.network("Request failed [\(layer.rawValue)] for \(op): HTTP \(http.statusCode). \(payloadSummary)")
        }

        APIDiagnostics.log("request.ok op=\(op) layer=\(layer.rawValue) status=\(http.statusCode)")
        do {
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            return try decoder.decode(T.self, from: data)
        } catch {
            APIDiagnostics.log("request.decode_fail op=\(op) layer=\(layer.rawValue) error=\(error.localizedDescription)")
            throw AppError.malformedResponse("Decoding failed for \(op): \(error.localizedDescription)")
        }
    }
}

private struct AuthResponse: Codable {
    struct User: Codable {
        let id: UUID
        let email: String?
    }

    let accessToken: String?
    let refreshToken: String?
    let user: User?
    let errorDescription: String?
    let msg: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
        case errorDescription = "error_description"
        case msg
    }
}

private struct GenerateDocsResponse: Codable {
    let contractVersionID: UUID
    let documents: [BrainDocument]

    enum CodingKeys: String, CodingKey {
        case contractVersionID = "contract_version_id"
        case documents
    }
}

private struct RequirementRow: Codable {
    let id: UUID
    let projectID: UUID
    let cycleNo: Int
    let contractVersionID: UUID
    let contractDocID: UUID
    let roleID: Int
    let requirementText: String
    let trustLabel: TrustLabel
    let requirementIndex: Int

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case cycleNo = "cycle_no"
        case contractVersionID = "contract_version_id"
        case contractDocID = "contract_doc_id"
        case roleID = "role_id"
        case requirementText = "requirement_text"
        case trustLabel = "trust_label"
        case requirementIndex = "requirement_index"
    }
}

private struct ProvenancePointerRow: Codable {
    let requirementID: UUID
    let pointer: String

    enum CodingKeys: String, CodingKey {
        case requirementID = "requirement_id"
        case pointer
    }
}

private struct AnyDecodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyDecodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyDecodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }
}

private struct EmptyResponse: Decodable {}

private extension Encodable {
    func toDictionary() throws -> [String: Any] {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.malformedResponse("Failed to encode request payload.")
        }
        return object
    }
}
