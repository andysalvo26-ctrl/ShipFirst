import Foundation

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let userID: UUID
    let email: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case userID = "user_id"
        case email
        case expiresAt = "expires_at"
    }
}

struct ProjectSummary: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let ideaSentence: String
    let websiteURL: String?
    let readinessState: String
    let activeRevision: Int
    let updatedAt: String
    let hasBrief: Bool?
    let latestVersionNo: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case ideaSentence = "idea_sentence"
        case websiteURL = "website_url"
        case readinessState = "readiness_state"
        case activeRevision = "active_revision"
        case updatedAt = "updated_at"
        case hasBrief = "has_brief"
        case latestVersionNo = "latest_version_no"
    }
}

struct Readiness: Codable, Equatable {
    enum State: String, Codable {
        case notReady = "not_ready"
        case ready
    }

    let state: State
    let reason: String
    let resolvedRequired: Int
    let totalRequired: Int
    let missingRequired: [String]
    let missingOptional: [String]
}

struct QuestionOption: Codable, Equatable, Identifiable {
    let id: String
    let label: String
}

struct IntakeQuestion: Codable, Equatable {
    let key: String
    let prompt: String
    let options: [QuestionOption]
    let allowFreeText: Bool
}

struct IntakeState: Codable, Equatable {
    let readiness: Readiness
    let nextQuestion: IntakeQuestion?
    let canGenerate: Bool
    let canImprove: Bool
    let statusMessage: String

    enum CodingKeys: String, CodingKey {
        case readiness
        case nextQuestion = "next_question"
        case canGenerate = "can_generate"
        case canImprove = "can_improve"
        case statusMessage = "status_message"
    }
}

struct BriefDoc: Codable, Equatable, Identifiable {
    let key: String
    let title: String
    let body: String

    var id: String { key }
}

struct ProjectStateResponse: Codable, Equatable {
    let project: ProjectSummary
    let state: IntakeState
    let latestBrief: LatestBrief?

    struct LatestBrief: Codable, Equatable {
        let versionNo: Int
        let createdAt: String
        let docs: [BriefDoc]

        enum CodingKeys: String, CodingKey {
            case versionNo = "version_no"
            case createdAt = "created_at"
            case docs
        }
    }

    enum CodingKeys: String, CodingKey {
        case project
        case state
        case latestBrief = "latest_brief"
    }
}

struct ProjectsResponse: Codable, Equatable {
    let projects: [ProjectSummary]
}

struct TurnResponse: Codable, Equatable {
    let projectID: UUID
    let revisionNo: Int
    let readiness: Readiness
    let nextQuestion: IntakeQuestion?
    let canGenerate: Bool
    let canImprove: Bool
    let statusMessage: String

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case revisionNo = "revision_no"
        case readiness
        case nextQuestion = "next_question"
        case canGenerate = "can_generate"
        case canImprove = "can_improve"
        case statusMessage = "status_message"
    }
}

struct GenerateResponse: Codable, Equatable {
    let projectID: UUID
    let revisionNo: Int
    let versionNo: Int
    let createdAt: String
    let generationMode: String
    let readiness: Readiness
    let docs: [BriefDoc]

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case revisionNo = "revision_no"
        case versionNo = "version_no"
        case createdAt = "created_at"
        case generationMode = "generation_mode"
        case readiness
        case docs
    }
}

struct APIErrorEnvelope: Decodable {
    let error: APIErrorPayload
}

struct APIErrorPayload: Decodable {
    let code: String?
    let message: String?
    let layer: String?
}
