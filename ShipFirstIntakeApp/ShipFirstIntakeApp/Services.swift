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
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let message): return message
        case .network(let message): return message
        case .unauthorized: return "Your session is not authorized. Please sign in again."
        case .malformedResponse(let message): return message
        }
    }
}

private enum SessionStore {
    static let key = "shipfirst.auth.session"

    static func load() -> AuthSession? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    static func save(_ session: AuthSession?) {
        if let session {
            let data = try? JSONEncoder().encode(session)
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
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
    let api: SupabaseAPI?

    init() {
        do {
            let config = try RuntimeConfig.fromBundle()
            print("ShipFirst config loaded: url=\(config.supabaseURL.absoluteString), anon=\(RuntimeConfig.redacted(config.supabaseAnonKey))")
            let loadedSession = SessionStore.load()
            self.session = loadedSession
            self.sessionReference.value = loadedSession
            let ref = self.sessionReference
            self.api = SupabaseAPI(config: config) { ref.value }
            self.isReady = true
        } catch {
            self.api = nil
            self.configError = error.localizedDescription
            self.isReady = false
        }
    }

    func saveSession(_ session: AuthSession?) {
        self.session = session
        self.sessionReference.value = session
        SessionStore.save(session)
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
    let createdAt: String
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserID = "owner_user_id"
        case name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct ContractVersionListRow: Decodable {
    let id: UUID
    let projectID: UUID
    let cycleNo: Int
    let versionNumber: Int?
    let status: String?
    let createdAt: String
    let submissionBundlePath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case cycleNo = "cycle_no"
        case versionNumber = "version_number"
        case status
        case createdAt = "created_at"
        case submissionBundlePath = "submission_bundle_path"
    }
}

final class SupabaseAPI {
    private let config: RuntimeConfig
    private let sessionProvider: () -> AuthSession?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(config: RuntimeConfig, sessionProvider: @escaping () -> AuthSession?) {
        self.config = config
        self.sessionProvider = sessionProvider
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
        return try buildSession(from: response)
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
        return try buildSession(from: response)
    }

    private func buildSession(from response: AuthResponse) throws -> AuthSession {
        guard let accessToken = response.accessToken,
              let refreshToken = response.refreshToken,
              let user = response.user,
              let email = user.email else {
            throw AppError.malformedResponse(response.errorDescription ?? response.msg ?? "Auth response missing session fields.")
        }

        return AuthSession(accessToken: accessToken, refreshToken: refreshToken, userID: user.id, email: email)
    }

    // MARK: Runs (mapped to project + cycle)
    func listRuns() async throws -> [RunSummary] {
        let projectURL = try postgrestURL(path: "projects", query: "select=id,owner_user_id,name,created_at,updated_at&order=created_at.desc")
        let projects: [ProjectRow] = try await request(url: projectURL, method: "GET", bearerToken: requiredSession().accessToken)

        let versionsURL = try postgrestURL(path: "contract_versions", query: "select=id,project_id,cycle_no,version_number,status,created_at,submission_bundle_path&order=created_at.desc")
        let versions: [ContractVersionListRow] = try await request(url: versionsURL, method: "GET", bearerToken: requiredSession().accessToken)

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
                        cycleNo: 1,
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
                    output.append(
                        RunSummary(
                            projectID: row.projectID,
                            cycleNo: row.cycleNo,
                            title: project.name ?? "Untitled Project",
                            status: row.status ?? "generated",
                            latestContractVersionID: row.id,
                            latestSubmissionPath: row.submissionBundlePath,
                            createdAt: row.createdAt,
                            updatedAt: row.createdAt,
                            submittedAt: row.submissionBundlePath == nil ? nil : row.createdAt
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
        let url = try postgrestURL(path: "projects", query: "select=id,owner_user_id,name,created_at,updated_at")
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
            cycleNo: 1,
            title: project.name ?? "Untitled Project",
            status: "draft",
            latestContractVersionID: nil,
            latestSubmissionPath: nil,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt ?? project.createdAt,
            submittedAt: nil
        )
    }

    func listIntakeTurns(projectID: UUID, cycleNo: Int) async throws -> [IntakeTurn] {
        let query = "project_id=eq.\(projectID.uuidString)&cycle_no=eq.\(cycleNo)&select=id,project_id,cycle_no,turn_index,raw_text,created_at&order=turn_index.asc"
        let url = try postgrestURL(path: "intake_turns", query: query)
        return try await request(url: url, method: "GET", bearerToken: requiredSession().accessToken)
    }

    func addIntakeTurn(projectID: UUID, cycleNo: Int, text: String, turnIndex: Int) async throws -> IntakeTurn {
        let payload: [String: Any] = [
            "project_id": projectID.uuidString,
            "cycle_no": cycleNo,
            "turn_index": turnIndex,
            "raw_text": text,
            "actor_type": "USER",
        ]
        let url = try postgrestURL(path: "intake_turns", query: "select=id,project_id,cycle_no,turn_index,raw_text,created_at")
        let inserted: [IntakeTurn] = try await request(
            url: url,
            method: "POST",
            bearerToken: requiredSession().accessToken,
            bodyAny: payload,
            extraHeaders: ["Prefer": "return=representation"]
        )
        guard let item = inserted.first else {
            throw AppError.malformedResponse("Intake insert returned no row.")
        }
        return item
    }

    func listDecisionItems(projectID: UUID, cycleNo: Int) async throws -> [DecisionItem] {
        let query = "project_id=eq.\(projectID.uuidString)&cycle_no=eq.\(cycleNo)&select=id,project_id,cycle_no,decision_key,claim,status,evidence_refs,lock_state,updated_at&order=updated_at.desc"
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
        let versionQuery = "project_id=eq.\(projectID.uuidString)&cycle_no=eq.\(cycleNo)&select=id,project_id,cycle_no,version_number,status,created_at,submission_bundle_path&order=version_number.desc&limit=1"
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
        let refsByRequirement = Dictionary(grouping: provenance, by: \ .requirementID)

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
                provenanceRefs: refsByRequirement[row.id]?.map(\ .pointer) ?? [],
                claimIndex: row.requirementIndex
            )
        }, by: \ .contractDocID)

        docs = docs.map { doc in
            var copy = doc
            copy.claims = claimByDoc[doc.id] ?? []
            return copy
        }

        return docs
    }

    func generateDocuments(projectID: UUID, cycleNo: Int, regenerateRoleIDs: [Int]? = nil) async throws -> [BrainDocument] {
        let endpoint = config.supabaseURL.appendingPathComponent("functions/v1/generate-docs")
        var payload: [String: Any] = ["project_id": projectID.uuidString, "cycle_no": cycleNo]
        if let regenerateRoleIDs { payload["regenerate_role_ids"] = regenerateRoleIDs }

        let response: GenerateDocsResponse = try await request(
            url: endpoint,
            method: "POST",
            bearerToken: requiredSession().accessToken,
            bodyAny: payload
        )
        return response.documents
    }

    func submitRun(projectID: UUID, cycleNo: Int) async throws -> SubmissionResult {
        let endpoint = config.supabaseURL.appendingPathComponent("functions/v1/submit-run")
        let payload: [String: Any] = ["project_id": projectID.uuidString, "cycle_no": cycleNo]
        return try await request(
            url: endpoint,
            method: "POST",
            bearerToken: requiredSession().accessToken,
            bodyAny: payload
        )
    }

    private func requiredSession() throws -> AuthSession {
        guard let session = sessionProvider() else {
            throw AppError.unauthorized
        }
        return session
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
        requiresAuth: Bool = true
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")

        if requiresAuth {
            guard let bearerToken else { throw AppError.unauthorized }
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body {
            request.httpBody = try encoder.encode(body)
        } else if let bodyAny {
            request.httpBody = try JSONSerialization.data(withJSONObject: bodyAny)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AppError.network("Invalid HTTP response")
        }

        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            if http.statusCode == 401 || http.statusCode == 403 {
                throw AppError.unauthorized
            }
            throw AppError.network(message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppError.malformedResponse("Decoding failed: \(error.localizedDescription)")
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
