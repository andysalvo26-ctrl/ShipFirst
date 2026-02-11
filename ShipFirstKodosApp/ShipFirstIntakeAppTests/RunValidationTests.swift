import XCTest
@testable import ShipFirstIntake

final class RunValidationTests: XCTestCase {
    private func makeDecision(
        key: String,
        status: TrustLabel = .userSaid,
        decisionState: DecisionState = .confirmed,
        hasConflict: Bool = false
    ) -> DecisionItem {
        DecisionItem(
            id: UUID(),
            projectID: UUID(),
            cycleNo: 1,
            decisionKey: key,
            claim: "Claim for \(key)",
            status: status,
            decisionState: decisionState,
            evidenceRefs: ["turn:1"],
            lockState: decisionState == .confirmed ? .locked : .open,
            confirmedByTurnID: (decisionState == .confirmed && status == .userSaid) ? UUID() : nil,
            hasConflict: hasConflict,
            conflictKey: hasConflict ? key : nil,
            updatedAt: "2026-01-01T00:00:00Z"
        )
    }

    func testValidationPassesForCompleteTenRoles() {
        let projectID = UUID()
        let cycleNo = 1
        let versionID = UUID()
        let docs = RoleCatalog.orderedRoles.map { role in
            BrainDocument(
                id: UUID(),
                projectID: projectID,
                cycleNo: cycleNo,
                contractVersionID: versionID,
                roleID: role.id,
                title: role.displayName,
                body: "Body",
                isComplete: true,
                createdAt: "2026-01-01T00:00:00Z",
                claims: [
                    DocumentClaim(
                        id: UUID(),
                        projectID: projectID,
                        cycleNo: cycleNo,
                        contractVersionID: versionID,
                        contractDocID: UUID(),
                        roleID: role.id,
                        claimText: "Claim",
                        trustLabel: .userSaid,
                        provenanceRefs: ["turn:1"],
                        claimIndex: 0
                    )
                ]
            )
        }

        let result = RunValidator.validate(documents: docs)
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testValidationFailsWhenRoleMissing() {
        let projectID = UUID()
        let cycleNo = 1
        let versionID = UUID()
        var docs = RoleCatalog.orderedRoles.map { role in
            BrainDocument(
                id: UUID(),
                projectID: projectID,
                cycleNo: cycleNo,
                contractVersionID: versionID,
                roleID: role.id,
                title: role.displayName,
                body: "Body",
                isComplete: true,
                createdAt: "2026-01-01T00:00:00Z",
                claims: [
                    DocumentClaim(
                        id: UUID(),
                        projectID: projectID,
                        cycleNo: cycleNo,
                        contractVersionID: versionID,
                        contractDocID: UUID(),
                        roleID: role.id,
                        claimText: "Claim",
                        trustLabel: .userSaid,
                        provenanceRefs: ["turn:1"],
                        claimIndex: 0
                    )
                ]
            )
        }
        docs.removeLast()

        let result = RunValidator.validate(documents: docs)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.joined(separator: " ").contains("Missing required roles"))
    }

    func testValidationFailsWhenContractVersionsAreMixed() {
        let projectID = UUID()
        let cycleNo = 1
        let versionA = UUID()
        let versionB = UUID()
        let docs = RoleCatalog.orderedRoles.enumerated().map { index, role in
            BrainDocument(
                id: UUID(),
                projectID: projectID,
                cycleNo: cycleNo,
                contractVersionID: index == 0 ? versionA : versionB,
                roleID: role.id,
                title: role.displayName,
                body: "Body",
                isComplete: true,
                createdAt: "2026-01-01T00:00:00Z",
                claims: [
                    DocumentClaim(
                        id: UUID(),
                        projectID: projectID,
                        cycleNo: cycleNo,
                        contractVersionID: index == 0 ? versionA : versionB,
                        contractDocID: UUID(),
                        roleID: role.id,
                        claimText: "Claim",
                        trustLabel: .userSaid,
                        provenanceRefs: ["turn:1"],
                        claimIndex: 0
                    )
                ]
            )
        }

        let result = RunValidator.validate(documents: docs)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains(where: { $0.contains("one contract version") }))
    }

    func testValidationFailsWhenProvenanceMissing() {
        let projectID = UUID()
        let cycleNo = 1
        let versionID = UUID()
        let docs = RoleCatalog.orderedRoles.map { role in
            BrainDocument(
                id: UUID(),
                projectID: projectID,
                cycleNo: cycleNo,
                contractVersionID: versionID,
                roleID: role.id,
                title: role.displayName,
                body: "Body",
                isComplete: true,
                createdAt: "2026-01-01T00:00:00Z",
                claims: [
                    DocumentClaim(
                        id: UUID(),
                        projectID: projectID,
                        cycleNo: cycleNo,
                        contractVersionID: versionID,
                        contractDocID: UUID(),
                        roleID: role.id,
                        claimText: "Claim",
                        trustLabel: .assumed,
                        provenanceRefs: [],
                        claimIndex: 0
                    )
                ]
            )
        }

        let result = RunValidator.validate(documents: docs)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains(where: { $0.contains("missing provenance") }))
    }

    func testCommitReadinessRequiresAllCoreDecisions() {
        let readiness = CommitReadinessEvaluator.evaluate(decisions: [
            makeDecision(key: "primary_outcome", status: .unknown, decisionState: .proposed)
        ])
        XCTAssertFalse(readiness.canCommit)
        XCTAssertTrue(readiness.blockers.contains(where: { $0.contains("Business type") }))
        XCTAssertTrue(readiness.blockers.contains(where: { $0.contains("Version-one capabilities") }))
        XCTAssertTrue(readiness.blockers.contains(where: { $0.contains("Payment approach") }))
    }

    func testCommitReadinessFailsOnConflict() {
        let readiness = CommitReadinessEvaluator.evaluate(decisions: [
            makeDecision(key: "business_type", status: .userSaid, decisionState: .confirmed),
            makeDecision(key: "business_type_conflict", status: .unknown, decisionState: .proposed, hasConflict: true)
        ])
        XCTAssertFalse(readiness.canCommit)
        XCTAssertTrue(readiness.blockers.contains(where: { $0.contains("contradiction") }))
    }

    func testCommitReadinessPassesWhenAllCoreDecisionsConfirmedAndNoConflict() {
        let readiness = CommitReadinessEvaluator.evaluate(decisions: [
            makeDecision(key: "business_type", status: .userSaid, decisionState: .confirmed),
            makeDecision(key: "primary_outcome", status: .userSaid, decisionState: .confirmed),
            makeDecision(key: "launch_capabilities", status: .userSaid, decisionState: .confirmed),
            makeDecision(key: "monetization_path", status: .userSaid, decisionState: .confirmed)
        ])
        XCTAssertTrue(readiness.canCommit, "blockers: \(readiness.blockers)")
        XCTAssertTrue(readiness.blockers.isEmpty, "blockers: \(readiness.blockers)")
    }

    func testCommitReadinessFailsWhenCoreDecisionNotExplicitlyConfirmed() {
        let readiness = CommitReadinessEvaluator.evaluate(decisions: [
            makeDecision(key: "business_type", status: .userSaid, decisionState: .confirmed),
            makeDecision(key: "primary_outcome", status: .userSaid, decisionState: .confirmed),
            makeDecision(key: "launch_capabilities", status: .assumed, decisionState: .proposed),
            makeDecision(key: "monetization_path", status: .userSaid, decisionState: .confirmed)
        ])
        XCTAssertFalse(readiness.canCommit)
        XCTAssertTrue(readiness.blockers.contains(where: { $0.contains("Version-one capabilities") }))
    }

    func testNextTurnResponseDecodesRequiredPostureAndMove() throws {
        let json = """
        {
          "project_id":"A39BB2EE-7826-4E52-89A8-38FCD6FF59ED",
          "cycle_no":1,
          "user_turn_id":"2D8CC5C3-727F-49AF-9D34-26CDEBE65F5A",
          "assistant_turn_id":"316A00FA-1228-4E36-BFF2-A3AE33722288",
          "assistant_message":"What kind of business are you building?",
          "options":[{"id":"business_type:photography","label":"Photography"}],
          "posture_mode":"Alignment Checkpoint",
          "move_type":"MOVE_ALIGNMENT_CHECKPOINT",
          "unresolved":[],
          "can_commit":false,
          "commit_blockers":["Business type is not explicitly confirmed yet."],
          "provenance_refs":[],
          "trace":{
            "correlation_id":"test-correlation",
            "project_id":"A39BB2EE-7826-4E52-89A8-38FCD6FF59ED",
            "cycle_no":1,
            "user_turn_id":"2D8CC5C3-727F-49AF-9D34-26CDEBE65F5A",
            "assistant_turn_id":"316A00FA-1228-4E36-BFF2-A3AE33722288"
          }
        }
        """

        let decoded = try JSONDecoder().decode(NextTurnResult.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.postureMode, .alignmentCheckpoint)
        XCTAssertEqual(decoded.moveType, .alignmentCheckpoint)
        XCTAssertFalse(decoded.canCommit)
    }

    func testNextTurnResponseFailsWithoutPostureOrMove() {
        let json = """
        {
          "project_id":"A39BB2EE-7826-4E52-89A8-38FCD6FF59ED",
          "cycle_no":1,
          "user_turn_id":"2D8CC5C3-727F-49AF-9D34-26CDEBE65F5A",
          "assistant_turn_id":"316A00FA-1228-4E36-BFF2-A3AE33722288",
          "assistant_message":"Question?",
          "options":[],
          "unresolved":[],
          "can_commit":false,
          "commit_blockers":[],
          "provenance_refs":[],
          "trace":{
            "correlation_id":"test-correlation",
            "project_id":"A39BB2EE-7826-4E52-89A8-38FCD6FF59ED",
            "cycle_no":1,
            "user_turn_id":"2D8CC5C3-727F-49AF-9D34-26CDEBE65F5A",
            "assistant_turn_id":"316A00FA-1228-4E36-BFF2-A3AE33722288"
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(NextTurnResult.self, from: Data(json.utf8)))
    }

    func testNextTurnRequestRequiresAtLeastOneActionableField() {
        let empty = NextTurnRequest(
            projectID: UUID(),
            cycleNo: 1,
            userMessage: nil,
            selectedOptionID: nil,
            noneFitText: nil,
            checkpointResponse: nil,
            artifactRef: nil,
            artifactType: nil,
            forceRefresh: nil
        )
        XCTAssertFalse(empty.hasActionableInput)

        let checkpoint = NextTurnRequest(
            projectID: UUID(),
            cycleNo: 1,
            userMessage: nil,
            selectedOptionID: nil,
            noneFitText: nil,
            checkpointResponse: NextTurnCheckpointResponse(
                checkpointID: UUID(),
                action: "confirm",
                optionalText: nil
            ),
            artifactRef: nil,
            artifactType: nil,
            forceRefresh: nil
        )
        XCTAssertTrue(checkpoint.hasActionableInput)
    }

    func testNextTurnResponseDecodesCheckpointCard() throws {
        let json = """
        {
          "project_id":"A39BB2EE-7826-4E52-89A8-38FCD6FF59ED",
          "cycle_no":1,
          "user_turn_id":"2D8CC5C3-727F-49AF-9D34-26CDEBE65F5A",
          "assistant_turn_id":"316A00FA-1228-4E36-BFF2-A3AE33722288",
          "assistant_message":"Please resolve the pending checkpoint to continue.",
          "options":[],
          "posture_mode":"Artifact Grounding",
          "move_type":"MOVE_REFLECT_VERIFY",
          "unresolved":[],
          "can_commit":false,
          "commit_blockers":["Website understanding is still unverified."],
          "checkpoint":{
            "id":"9A17FBF5-92E6-475F-BF45-D783696A0A97",
            "type":"artifact_verification",
            "status":"pending",
            "prompt":"Did I understand your website correctly?",
            "options":[
              {"id":"checkpoint:confirm","label":"Yes, correct"},
              {"id":"checkpoint:reject","label":"No, incorrect"}
            ],
            "requires_response":true
          },
          "provenance_refs":[],
          "trace":{
            "correlation_id":"test-correlation",
            "project_id":"A39BB2EE-7826-4E52-89A8-38FCD6FF59ED",
            "cycle_no":1,
            "user_turn_id":"2D8CC5C3-727F-49AF-9D34-26CDEBE65F5A",
            "assistant_turn_id":"316A00FA-1228-4E36-BFF2-A3AE33722288"
          }
        }
        """

        let decoded = try JSONDecoder().decode(NextTurnResult.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.checkpoint?.status, "pending")
        XCTAssertEqual(decoded.checkpoint?.options.first?.id, "checkpoint:confirm")
        XCTAssertEqual(decoded.postureMode, .artifactGrounding)
        XCTAssertEqual(decoded.moveType, .reflectVerify)
    }

    func testCanCommitRoutesToCommitReviewTask() {
        let task = KodosTurnTaskResolver.resolve(
            hasCompletedContextStep: true,
            pendingCheckpoint: nil,
            artifactState: nil,
            pendingOptions: [],
            canCommit: true,
            commitBlockers: ["business_type unconfirmed"]
        )

        switch task {
        case .commitReview(let blockers, let canCommit, _):
            XCTAssertTrue(canCommit)
            XCTAssertFalse(blockers.isEmpty)
        default:
            XCTFail("Expected commit review task when can_commit is true")
        }
    }

    func testPendingVerificationCheckpointRoutesToVerificationTask() {
        let checkpoint = NextTurnResult.Checkpoint(
            id: UUID(),
            type: "artifact_verification",
            status: "pending",
            prompt: "Please verify this summary.",
            options: [InterviewOption(id: "checkpoint:confirm", label: "Yes, correct")],
            requiresResponse: true
        )

        let artifact = NextTurnResult.ArtifactContextState(
            id: UUID(),
            artifactType: "website",
            artifactRef: "https://example.com",
            ingestState: "complete",
            verificationState: "unverified",
            statusMessage: nil,
            summaryText: "Summary",
            provenanceRefs: ["artifact:page:1"]
        )

        let task = KodosTurnTaskResolver.resolve(
            hasCompletedContextStep: true,
            pendingCheckpoint: checkpoint,
            artifactState: artifact,
            pendingOptions: [],
            canCommit: false,
            commitBlockers: []
        )

        switch task {
        case .verification(let routedCheckpoint, let routedArtifact):
            XCTAssertEqual(routedCheckpoint.id, checkpoint.id)
            XCTAssertEqual(routedArtifact?.artifactRef, artifact.artifactRef)
        default:
            XCTFail("Expected verification task when checkpoint requires a response")
        }
    }
}
