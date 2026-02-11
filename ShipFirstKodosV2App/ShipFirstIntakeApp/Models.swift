import Foundation

enum TrustLabel: String, Codable, CaseIterable {
    case userSaid = "USER_SAID"
    case assumed = "ASSUMED"
    case unknown = "UNKNOWN"
}

enum IntakeActor: String, Codable, CaseIterable {
    case user = "USER"
    case system = "SYSTEM"
}

enum DecisionLockState: String, Codable {
    case open
    case locked
}

enum DecisionState: String, Codable {
    case proposed = "PROPOSED"
    case confirmed = "CONFIRMED"
}

enum PostureMode: String, Codable, Equatable {
    case exploration = "Exploration"
    case artifactGrounding = "Artifact Grounding"
    case verification = "Verification"
    case extraction = "Extraction"
    case alignmentCheckpoint = "Alignment Checkpoint"
    case recovery = "Recovery"
}

enum MoveType: String, Codable, Equatable {
    case openDiscover = "MOVE_OPEN_DISCOVER"
    case reflectVerify = "MOVE_REFLECT_VERIFY"
    case targetedClarify = "MOVE_TARGETED_CLARIFY"
    case alignmentCheckpoint = "MOVE_ALIGNMENT_CHECKPOINT"
    case scopeReframe = "MOVE_SCOPE_REFRAME"
    case nuanceProbe = "MOVE_NUANCE_PROBE"
    case preserveUnknown = "MOVE_PRESERVE_UNKNOWN"
    case recoveryReset = "MOVE_RECOVERY_RESET"
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

struct RunSummary: Equatable, Hashable, Identifiable {
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
    let actorType: IntakeActor
    let turnIndex: Int
    let rawText: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case cycleNo = "cycle_no"
        case actorType = "actor_type"
        case turnIndex = "turn_index"
        case rawText = "raw_text"
        case createdAt = "created_at"
    }

    init(
        id: UUID,
        projectID: UUID,
        cycleNo: Int,
        actorType: IntakeActor,
        turnIndex: Int,
        rawText: String,
        createdAt: String
    ) {
        self.id = id
        self.projectID = projectID
        self.cycleNo = cycleNo
        self.actorType = actorType
        self.turnIndex = turnIndex
        self.rawText = rawText
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectID = try container.decode(UUID.self, forKey: .projectID)
        cycleNo = try container.decode(Int.self, forKey: .cycleNo)
        turnIndex = try container.decode(Int.self, forKey: .turnIndex)
        rawText = try container.decode(String.self, forKey: .rawText)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        actorType = (try? container.decode(IntakeActor.self, forKey: .actorType)) ?? .user
    }
}

struct DecisionItem: Codable, Identifiable, Equatable {
    let id: UUID
    let projectID: UUID
    let cycleNo: Int
    let decisionKey: String
    let claim: String
    let status: TrustLabel
    let decisionState: DecisionState
    let evidenceRefs: [String]
    let lockState: DecisionLockState
    let confirmedByTurnID: UUID?
    let hasConflict: Bool
    let conflictKey: String?
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
        case confirmedByTurnID = "confirmed_by_turn_id"
        case hasConflict = "has_conflict"
        case conflictKey = "conflict_key"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID,
        projectID: UUID,
        cycleNo: Int,
        decisionKey: String,
        claim: String,
        status: TrustLabel,
        decisionState: DecisionState,
        evidenceRefs: [String],
        lockState: DecisionLockState,
        confirmedByTurnID: UUID? = nil,
        hasConflict: Bool,
        conflictKey: String?,
        updatedAt: String
    ) {
        self.id = id
        self.projectID = projectID
        self.cycleNo = cycleNo
        self.decisionKey = decisionKey
        self.claim = claim
        self.status = status
        self.decisionState = decisionState
        self.evidenceRefs = evidenceRefs
        self.lockState = lockState
        self.confirmedByTurnID = confirmedByTurnID
        self.hasConflict = hasConflict
        self.conflictKey = conflictKey
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectID = try container.decode(UUID.self, forKey: .projectID)
        cycleNo = try container.decode(Int.self, forKey: .cycleNo)
        decisionKey = try container.decode(String.self, forKey: .decisionKey)
        claim = try container.decode(String.self, forKey: .claim)
        status = try container.decode(TrustLabel.self, forKey: .status)
        evidenceRefs = (try? container.decode([String].self, forKey: .evidenceRefs)) ?? []
        lockState = (try? container.decode(DecisionLockState.self, forKey: .lockState)) ?? .open
        confirmedByTurnID = try? container.decode(UUID.self, forKey: .confirmedByTurnID)
        decisionState = lockState == .locked ? .confirmed : .proposed
        hasConflict = (try? container.decode(Bool.self, forKey: .hasConflict)) ?? false
        conflictKey = try? container.decode(String.self, forKey: .conflictKey)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
    }
}

struct InterviewOption: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let label: String
}

struct UnresolvedDecision: Codable, Equatable, Identifiable {
    let id: UUID
    let decisionKey: String
    let claim: String
    let status: TrustLabel
    let decisionState: DecisionState
    let hasConflict: Bool
    let conflictKey: String?

    enum CodingKeys: String, CodingKey {
        case id
        case decisionKey = "decision_key"
        case claim
        case status
        case decisionState = "decision_state"
        case hasConflict = "has_conflict"
        case conflictKey = "conflict_key"
    }
}

struct NextTurnResult: Codable, Equatable {
    struct ReadinessBucket: Codable, Equatable, Identifiable {
        let key: String
        let label: String
        let status: String
        let detail: String

        var id: String { key }
    }

    struct Readiness: Codable, Equatable {
        let score: Int
        let resolvedCount: Int
        let totalCount: Int
        let nextFocus: String
        let buckets: [ReadinessBucket]

        enum CodingKeys: String, CodingKey {
            case score
            case resolvedCount = "resolved_count"
            case totalCount = "total_count"
            case nextFocus = "next_focus"
            case buckets
        }
    }

    struct Checkpoint: Codable, Equatable {
        let id: UUID
        let type: String
        let status: String
        let prompt: String
        let options: [InterviewOption]
        let requiresResponse: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case type
            case status
            case prompt
            case options
            case requiresResponse = "requires_response"
        }
    }

    struct Trace: Codable, Equatable {
        let correlationID: String
        let projectID: UUID
        let cycleNo: Int
        let userTurnID: UUID
        let assistantTurnID: UUID

        enum CodingKeys: String, CodingKey {
            case correlationID = "correlation_id"
            case projectID = "project_id"
            case cycleNo = "cycle_no"
            case userTurnID = "user_turn_id"
            case assistantTurnID = "assistant_turn_id"
        }
    }

    struct ArtifactContextState: Codable, Equatable {
        let id: UUID?
        let artifactType: String
        let artifactRef: String
        let ingestState: String
        let verificationState: String
        let statusMessage: String?
        let summaryText: String?
        let provenanceRefs: [String]

        enum CodingKeys: String, CodingKey {
            case id
            case artifactType = "artifact_type"
            case artifactRef = "artifact_ref"
            case ingestState = "ingest_state"
            case verificationState = "verification_state"
            case statusMessage = "status_message"
            case summaryText = "summary_text"
            case provenanceRefs = "provenance_refs"
        }
    }

    let projectID: UUID
    let cycleNo: Int
    let userTurnID: UUID
    let assistantTurnID: UUID
    let assistantMessage: String
    let options: [InterviewOption]
    let postureMode: PostureMode
    let moveType: MoveType
    let unresolved: [UnresolvedDecision]
    let canCommit: Bool
    let commitBlockers: [String]
    let qualityReady: Bool?
    let qualityBoostAvailable: Bool?
    let qualityHint: String?
    let readiness: Readiness?
    let checkpoint: Checkpoint?
    let artifact: ArtifactContextState?
    let provenanceRefs: [String]
    let trace: Trace

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case cycleNo = "cycle_no"
        case userTurnID = "user_turn_id"
        case assistantTurnID = "assistant_turn_id"
        case assistantMessage = "assistant_message"
        case options
        case postureMode = "posture_mode"
        case moveType = "move_type"
        case unresolved
        case canCommit = "can_commit"
        case commitBlockers = "commit_blockers"
        case qualityReady = "quality_ready"
        case qualityBoostAvailable = "quality_boost_available"
        case qualityHint = "quality_hint"
        case readiness
        case checkpoint
        case artifact
        case provenanceRefs = "provenance_refs"
        case trace
    }
}

struct NextTurnCheckpointResponse: Codable, Equatable {
    let checkpointID: UUID
    let action: String
    let optionalText: String?

    enum CodingKeys: String, CodingKey {
        case checkpointID = "checkpoint_id"
        case action
        case optionalText = "optional_text"
    }
}

struct NextTurnRequest: Codable, Equatable {
    let projectID: UUID
    let cycleNo: Int
    let userMessage: String?
    let selectedOptionID: String?
    let noneFitText: String?
    let checkpointResponse: NextTurnCheckpointResponse?
    let artifactRef: String?
    let artifactType: String?
    let forceRefresh: Bool?

    init(
        projectID: UUID,
        cycleNo: Int,
        userMessage: String? = nil,
        selectedOptionID: String? = nil,
        noneFitText: String? = nil,
        checkpointResponse: NextTurnCheckpointResponse? = nil,
        artifactRef: String? = nil,
        artifactType: String? = nil,
        forceRefresh: Bool? = nil
    ) {
        self.projectID = projectID
        self.cycleNo = cycleNo
        self.userMessage = userMessage
        self.selectedOptionID = selectedOptionID
        self.noneFitText = noneFitText
        self.checkpointResponse = checkpointResponse
        self.artifactRef = artifactRef
        self.artifactType = artifactType
        self.forceRefresh = forceRefresh
    }

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case cycleNo = "cycle_no"
        case userMessage = "user_message"
        case selectedOptionID = "selected_option_id"
        case noneFitText = "none_fit_text"
        case checkpointResponse = "checkpoint_response"
        case artifactRef = "artifact_ref"
        case artifactType = "artifact_type"
        case forceRefresh = "force_refresh"
    }

    var hasActionableInput: Bool {
        let hasUserMessage = !(userMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasSelectedOption = !(selectedOptionID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasArtifactRef = !(artifactRef?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasCheckpointResponse = checkpointResponse != nil
        return hasUserMessage || hasSelectedOption || hasArtifactRef || hasCheckpointResponse
    }
}

enum TypedActionKind: Equatable {
    case addEvidence(text: String)
    case selectOption(id: String, noneFitText: String?)
    case respondCheckpoint(id: UUID, action: String, optionalText: String?)
    case correctArtifactUnderstanding(id: UUID?, text: String)
    case deferUnknown(pointer: String, reason: String?)
    case requestCommit
    case confirmReviewAndSubmit
}

struct TypedAction: Equatable {
    let kind: TypedActionKind
}

enum TypedActionOutcome: Equatable {
    case turn(NextTurnResult)
    case commit(CommitContractResult)
    case submit(SubmissionResult)
}

struct CommitContractRequest: Codable, Equatable {
    let projectID: UUID
    let cycleNo: Int

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case cycleNo = "cycle_no"
    }
}

struct CommitContractResult: Codable, Equatable {
    struct Submission: Codable, Equatable {
        let submissionID: UUID
        let bucket: String
        let path: String
        let submittedAt: String

        enum CodingKeys: String, CodingKey {
            case submissionID = "submission_id"
            case bucket
            case path
            case submittedAt = "submitted_at"
        }
    }

    let contractVersionID: UUID
    let contractVersionNumber: Int
    let documents: [BrainDocument]
    let submission: Submission?
    let reviewRequired: Bool
    let reusedExistingVersion: Bool

    enum CodingKeys: String, CodingKey {
        case contractVersionID = "contract_version_id"
        case contractVersionNumber = "contract_version_number"
        case documents
        case submission
        case reviewRequired = "review_required"
        case reusedExistingVersion = "reused_existing_version"
    }
}

struct ContractVersionSummary: Codable, Identifiable, Equatable {
    let id: UUID
    let projectID: UUID
    let cycleNo: Int
    let versionNumber: Int
    let status: String
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

struct CommitReadinessResult: Equatable {
    let canCommit: Bool
    let blockers: [String]
}

enum CommitReadinessEvaluator {
    private static let requiredDecisionKeys: [String] = [
        "business_type",
        "primary_outcome",
        "launch_capabilities",
        "monetization_path",
    ]

    private static func isExplicitlyConfirmed(_ decision: DecisionItem) -> Bool {
        decision.status == .userSaid &&
        decision.lockState == .locked &&
        decision.confirmedByTurnID != nil
    }

    static func evaluate(decisions: [DecisionItem]) -> CommitReadinessResult {
        var blockers: [String] = []

        let latestByKey: [String: DecisionItem] = Dictionary(grouping: decisions, by: \.decisionKey)
            .reduce(into: [:]) { partial, entry in
                if let latest = entry.value.max(by: { $0.updatedAt < $1.updatedAt }) {
                    partial[entry.key] = latest
                }
            }

        for key in requiredDecisionKeys {
            guard let decision = latestByKey[key], isExplicitlyConfirmed(decision) else {
                switch key {
                case "business_type":
                    blockers.append("Business type is not confirmed yet.")
                case "primary_outcome":
                    blockers.append("First customer outcome is not confirmed yet.")
                case "launch_capabilities":
                    blockers.append("Version-one capabilities are not confirmed yet.")
                case "monetization_path":
                    blockers.append("Payment approach is not confirmed yet.")
                default:
                    blockers.append("A required setup answer is still unconfirmed.")
                }
                continue
            }
        }

        if decisions.contains(where: \.hasConflict) {
            blockers.append("At least one contradiction is unresolved.")
        }
        return CommitReadinessResult(canCommit: blockers.isEmpty, blockers: blockers)
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
