import Foundation

enum TrustLabel: String, Codable, CaseIterable {
    case userSaid = "USER_SAID"
    case assumed = "ASSUMED"
    case unknown = "UNKNOWN"
}

enum DecisionLockState: String, Codable {
    case open
    case locked
}

struct DocumentRole: Identifiable, Hashable {
    let id: Int
    let key: String
    let displayName: String
}

enum RoleCatalog {
    static let orderedRoles: [DocumentRole] = [
        .init(id: 1, key: "NORTH_STAR", displayName: "North Star"),
        .init(id: 2, key: "USER_STORY_MAP", displayName: "User Story Map"),
        .init(id: 3, key: "SCOPE_BOUNDARY", displayName: "Scope Boundary"),
        .init(id: 4, key: "FEATURES_PRIORITIZED", displayName: "Features Prioritized"),
        .init(id: 5, key: "DATA_MODEL", displayName: "Data Model"),
        .init(id: 6, key: "INTEGRATIONS", displayName: "Integrations"),
        .init(id: 7, key: "UX_NOTES", displayName: "UX Notes"),
        .init(id: 8, key: "RISKS_OPEN_QUESTIONS", displayName: "Risks and Open Questions"),
        .init(id: 9, key: "BUILD_PLAN", displayName: "Build Plan"),
        .init(id: 10, key: "ACCEPTANCE_TESTS", displayName: "Acceptance Tests"),
    ]

    static let requiredRoleIDs: Set<Int> = Set(orderedRoles.map(\.id))

    static func role(for id: Int) -> DocumentRole {
        orderedRoles.first(where: { $0.id == id }) ?? .init(id: id, key: "ROLE_\(id)", displayName: "Role \(id)")
    }
}

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let userID: UUID
    let email: String
}

struct RunSummary: Equatable, Identifiable {
    let projectID: UUID
    let cycleNo: Int
    let title: String
    let status: String
    let latestContractVersionID: UUID?
    let latestSubmissionPath: String?
    let createdAt: String
    let updatedAt: String
    let submittedAt: String?

    var id: String { "\(projectID.uuidString):\(cycleNo)" }
}

struct IntakeTurn: Codable, Identifiable, Equatable {
    let id: UUID
    let projectID: UUID
    let cycleNo: Int
    let turnIndex: Int
    let rawText: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case cycleNo = "cycle_no"
        case turnIndex = "turn_index"
        case rawText = "raw_text"
        case createdAt = "created_at"
    }
}

struct DecisionItem: Codable, Identifiable, Equatable {
    let id: UUID
    let projectID: UUID
    let cycleNo: Int
    let decisionKey: String
    let claim: String
    let status: TrustLabel
    let evidenceRefs: [String]
    let lockState: DecisionLockState
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case cycleNo = "cycle_no"
        case decisionKey = "decision_key"
        case claim
        case status
        case evidenceRefs = "evidence_refs"
        case lockState = "lock_state"
        case updatedAt = "updated_at"
    }
}

struct ContractVersionSummary: Codable, Identifiable, Equatable {
    let id: UUID
    let projectID: UUID
    let cycleNo: Int
    let versionNumber: Int
    let status: String
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

struct DocumentClaim: Codable, Identifiable, Equatable {
    let id: UUID
    let projectID: UUID
    let cycleNo: Int
    let contractVersionID: UUID
    let contractDocID: UUID
    let roleID: Int
    let claimText: String
    let trustLabel: TrustLabel
    let provenanceRefs: [String]
    let claimIndex: Int

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case cycleNo = "cycle_no"
        case contractVersionID = "contract_version_id"
        case contractDocID = "contract_doc_id"
        case roleID = "role_id"
        case claimText = "claim_text"
        case trustLabel = "trust_label"
        case provenanceRefs = "provenance_refs"
        case claimIndex = "claim_index"
    }
}

struct BrainDocument: Codable, Identifiable, Equatable {
    let id: UUID
    let projectID: UUID
    let cycleNo: Int
    let contractVersionID: UUID
    let roleID: Int
    let title: String
    let body: String
    let isComplete: Bool
    let createdAt: String
    var claims: [DocumentClaim]

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case cycleNo = "cycle_no"
        case contractVersionID = "contract_version_id"
        case roleID = "role_id"
        case title
        case body
        case isComplete = "is_complete"
        case createdAt = "created_at"
        case claims
    }
}

struct SubmissionResult: Codable, Equatable {
    let submissionID: UUID
    let contractVersionID: UUID
    let bucket: String
    let path: String
    let submittedAt: String

    enum CodingKeys: String, CodingKey {
        case submissionID = "submission_id"
        case contractVersionID = "contract_version_id"
        case bucket
        case path
        case submittedAt = "submitted_at"
    }
}

struct DocumentValidationResult: Equatable {
    let isValid: Bool
    let issues: [String]

    static let empty = DocumentValidationResult(isValid: false, issues: ["No documents generated yet."])
}

enum RunValidator {
    static func validate(documents: [BrainDocument]) -> DocumentValidationResult {
        guard !documents.isEmpty else { return .empty }

        var issues: [String] = []
        if documents.count != 10 {
            issues.append("Exactly 10 documents are required. Found \(documents.count).")
        }

        let roleIDs = Set(documents.map(\.roleID))

        if roleIDs != RoleCatalog.requiredRoleIDs {
            let missing = RoleCatalog.requiredRoleIDs.subtracting(roleIDs).sorted()
            let extras = roleIDs.subtracting(RoleCatalog.requiredRoleIDs).sorted()
            if !missing.isEmpty { issues.append("Missing required roles: \(missing.map(String.init).joined(separator: ", ")).") }
            if !extras.isEmpty { issues.append("Unexpected role ids: \(extras.map(String.init).joined(separator: ", ")).") }
        }

        let duplicateRoleIDs = Dictionary(grouping: documents, by: \.roleID)
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
        if !duplicateRoleIDs.isEmpty {
            issues.append("Duplicate role ids found: \(duplicateRoleIDs.map(String.init).joined(separator: ", ")).")
        }

        let versionIDs = Set(documents.map(\.contractVersionID))
        if versionIDs.count != 1 {
            issues.append("Documents must come from one contract version.")
        }

        for doc in documents {
            if !doc.isComplete {
                issues.append("Role \(doc.roleID) is incomplete.")
            }
            if doc.claims.isEmpty {
                issues.append("Role \(doc.roleID) has no claims.")
            }

            for claim in doc.claims {
                if claim.claimText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append("Role \(doc.roleID) has a blank claim.")
                }
                if claim.provenanceRefs.isEmpty {
                    issues.append("Role \(doc.roleID) claim \(claim.claimIndex) missing provenance.")
                }
            }
        }

        return DocumentValidationResult(isValid: issues.isEmpty, issues: issues)
    }
}

struct SubmissionManifest: Codable, Equatable {
    struct DocumentMeta: Codable, Equatable {
        let roleID: Int
        let roleKey: String
        let title: String
        let claimCount: Int

        enum CodingKeys: String, CodingKey {
            case roleID = "role_id"
            case roleKey = "role_key"
            case title
            case claimCount = "claim_count"
        }
    }

    let runID: UUID
    let userID: UUID
    let submittedAt: String
    let documentCount: Int
    let documents: [DocumentMeta]

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case userID = "user_id"
        case submittedAt = "submitted_at"
        case documentCount = "document_count"
        case documents
    }
}

enum SubmissionManifestBuilder {
    static func build(runID: UUID, userID: UUID, submittedAt: String, documents: [BrainDocument]) -> SubmissionManifest {
        let docMeta = documents
            .sorted(by: { $0.roleID < $1.roleID })
            .map { doc in
                SubmissionManifest.DocumentMeta(
                    roleID: doc.roleID,
                    roleKey: RoleCatalog.role(for: doc.roleID).key,
                    title: doc.title,
                    claimCount: doc.claims.count
                )
            }

        return SubmissionManifest(
            runID: runID,
            userID: userID,
            submittedAt: submittedAt,
            documentCount: docMeta.count,
            documents: docMeta
        )
    }
}
