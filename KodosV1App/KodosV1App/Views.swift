import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if !appState.isReady {
                VStack(spacing: 12) {
                    Text("Configuration Error")
                        .font(.headline)
                    Text(appState.configError ?? "Missing app configuration.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            } else if appState.session == nil {
                AuthView()
            } else {
                RunsView()
            }
        }
    }
}

struct AuthView: View {
    @EnvironmentObject private var appState: AppState

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSignInMode: Bool = true
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Email", text: $email)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                    SecureField("Password", text: $password)
                }

                Section {
                    Button(isSignInMode ? "Sign In" : "Create Account") {
                        Task { await authenticate() }
                    }
                    .disabled(isLoading || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)

                    Button(isSignInMode ? "Need an account? Sign Up" : "Have an account? Sign In") {
                        isSignInMode.toggle()
                        errorMessage = nil
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("ShipFirst Intake")
        }
    }

    private func authenticate() async {
        guard let api = appState.api else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let session: AuthSession
            if isSignInMode {
                session = try await api.signIn(email: email, password: password)
            } else {
                session = try await api.signUp(email: email, password: password)
            }
            appState.saveSession(session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct RunsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var runs: [RunSummary] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if runs.isEmpty && !isLoading {
                    Text("No runs yet. Create a new run to start intake.")
                        .foregroundStyle(.secondary)
                }

                ForEach(runs) { run in
                    NavigationLink {
                        RunDetailView(run: run)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(run.title) • Cycle \(run.cycleNo)")
                                .font(.headline)
                            Text("Status: \(run.status)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Your Runs")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign Out") {
                        appState.signOut()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Run") {
                        Task { await createRun() }
                    }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
            .task {
                await loadRuns()
            }
            .refreshable {
                await loadRuns()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
                Button("OK") { errorMessage = nil }
            } message: { message in
                Text(message)
            }
        }
    }

    private func loadRuns() async {
        guard let api = appState.api else { return }
#if DEBUG
        if let session = appState.session {
            let claims = SessionInspector.jwtIssueAndExpiry(accessToken: session.accessToken)
            print("[ShipFirstRuns] loadRuns session user=\(session.userID.uuidString) issued_at=\(claims.issuedAt ?? "unknown") expires_at=\(claims.expiresAt ?? "unknown") token=\(SessionInspector.redactedToken(session.accessToken))")
        } else {
            print("[ShipFirstRuns] loadRuns no active session")
        }
#endif
        isLoading = true
        defer { isLoading = false }

        do {
            runs = try await api.listRuns()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createRun() async {
        guard let api = appState.api else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await api.createRun()
            runs = try await api.listRuns()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct RunDetailView: View {
    @EnvironmentObject private var appState: AppState

    let run: RunSummary

    @State private var intakeTurns: [IntakeTurn] = []
    @State private var decisions: [DecisionItem] = []
    @State private var documents: [BrainDocument] = []
    @State private var activeCycleNo: Int
    @State private var intakeInput: String = ""
    @State private var artifactURLInput: String = ""
    @State private var selectedSegment: Segment = .intake
    @State private var pendingOptions: [InterviewOption] = []
    @State private var pendingCheckpoint: NextTurnResult.Checkpoint?
    @State private var serverUnresolved: [UnresolvedDecision] = []
    @State private var commitBlockers: [String] = []
    @State private var lastPostureMode: PostureMode?
    @State private var lastMoveType: MoveType?
    @State private var canCommit: Bool = false
    @State private var latestArtifact: NextTurnResult.ArtifactContextState?
    @State private var artifactStatusMessage: String?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var submissionResult: SubmissionResult?

    enum Segment: String, CaseIterable {
        case intake = "Intake"
        case review = "Review"
    }

    init(run: RunSummary) {
        self.run = run
        self._activeCycleNo = State(initialValue: run.cycleNo)
    }

    private var unknownDecisions: [DecisionItem] {
        decisions.filter { $0.status == .unknown }
    }

    private var conflictDecisions: [DecisionItem] {
        decisions.filter(\.hasConflict)
    }

    private var validation: DocumentValidationResult {
        RunValidator.validate(documents: documents)
    }

    var body: some View {
        VStack {
            Picker("Stage", selection: $selectedSegment) {
                ForEach(Segment.allCases, id: \.self) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            if selectedSegment == .intake {
                intakeSurface
            } else {
                reviewSurface
            }
        }
        .navigationTitle("\(run.title) • C\(activeCycleNo)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Blank Canvas") {
                    Task { await startNewCycle() }
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .task {
            await reloadAll()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
            Button("OK") { errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private var intakeSurface: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Interview")
                        .font(.headline)
                    Text("Start open-ended, then lock key decisions through explicit checkpoints.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Website (optional)")
                            .font(.headline)
                        HStack(spacing: 8) {
                            TextField("https://your-site.com", text: $artifactURLInput)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .keyboardType(.URL)
                                .textFieldStyle(.roundedBorder)
                            Button("Read") {
                                Task { await ingestArtifactURL(forceRefresh: false) }
                            }
                            .disabled(artifactURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if let artifact = latestArtifact {
                            Text("Artifact: \(artifact.ingestState) • verification: \(artifact.verificationState)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let status = artifactStatusMessage ?? artifact.statusMessage, !status.isEmpty {
                                Text(status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let summary = artifact.summaryText, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(summary)
                                    .font(.caption)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            if artifact.ingestState == "failed" || artifact.ingestState == "partial" {
                                Button("Retry Read") {
                                    Task { await ingestArtifactURL(forceRefresh: true) }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    ForEach(intakeTurns) { turn in
                        HStack {
                            if turn.actorType == .system {
                                assistantBubble(turn)
                                Spacer(minLength: 28)
                            } else {
                                Spacer(minLength: 28)
                                userBubble(turn)
                            }
                        }
                    }

                    TextEditor(text: $intakeInput)
                        .frame(minHeight: 90)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))

                    Button("Send") {
                        Task { await sendUserMessage() }
                    }
                    .disabled(intakeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

#if DEBUG
                    if let lastPostureMode, let lastMoveType {
                        Text("debug: \(lastPostureMode.rawValue) • \(lastMoveType.rawValue)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
#endif
                }

                if !pendingOptions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Alignment Checkpoint")
                            .font(.headline)
                        Text("Pick one option to confirm meaning, or choose None fit and continue in free text.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(pendingOptions) { option in
                                    Button(option.label) {
                                        Task { await submitOption(option) }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }

                if let checkpoint = pendingCheckpoint, checkpoint.requiresResponse {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Checkpoint")
                            .font(.headline)
                        Text(checkpoint.prompt)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(checkpoint.options) { option in
                                    Button(option.label) {
                                        Task { await submitCheckpointAction(checkpoint: checkpoint, option: option) }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Unknowns")
                        .font(.headline)

                    if unknownDecisions.isEmpty && serverUnresolved.isEmpty {
                        Text("No unknown decisions currently recorded.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(unknownDecisions) { decision in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(decision.decisionKey)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(decision.claim)
                                Text("Status: \(decision.status.rawValue)")
                                    .font(.caption)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        ForEach(serverUnresolved) { unresolved in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(unresolved.decisionKey)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(unresolved.claim)
                                Text("Status: \(unresolved.status.rawValue) • \(unresolved.decisionState.rawValue)")
                                    .font(.caption)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                if !conflictDecisions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Conflicts")
                            .font(.headline)
                        ForEach(conflictDecisions) { decision in
                            Text("• \(decision.claim)")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(canCommit ? "Commit is ready when you want to finalize." : "Commit is currently blocked.")
                        .foregroundStyle(canCommit ? .green : .secondary)
                    if !commitBlockers.isEmpty {
                        ForEach(commitBlockers, id: \.self) { blocker in
                            Text("• \(blocker)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button("Commit 10 Docs") {
                    Task { await commitContract() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private var reviewSurface: some View {
        List {
            Section("Validation") {
                if validation.isValid {
                    Text("All 10 roles are complete and submission-ready.")
                        .foregroundStyle(.green)
                } else {
                    ForEach(validation.issues, id: \.self) { issue in
                        Text(issue)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Documents") {
                ForEach(RoleCatalog.orderedRoles) { role in
                    if let document = documents.first(where: { $0.roleID == role.id }) {
                        NavigationLink {
                            DocumentDetailView(document: document)
                        } label: {
                            VStack(alignment: .leading) {
                                Text("\(role.id). \(role.displayName)")
                                Text(document.isComplete ? "Complete" : "Incomplete")
                                    .font(.caption)
                                    .foregroundStyle(document.isComplete ? .green : .orange)
                            }
                        }
                    } else {
                        VStack(alignment: .leading) {
                            Text("\(role.id). \(role.displayName)")
                            Text("Missing")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            Section("Finalize") {
                Button("Refresh Documents") {
                    Task { await reloadAll() }
                }

                Button("Commit 10 Docs") {
                    Task { await commitContract() }
                }
                .disabled(!validation.isValid)

                Button("Submit Bundle") {
                    Task { await submitBundle() }
                }
                .disabled(!validation.isValid)

                if let result = submissionResult {
                    Text("Bundle: \(result.path)")
                    Text("Submitted: \(result.submittedAt)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func userBubble(_ turn: IntakeTurn) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("You • #\(turn.turnIndex)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(turn.rawText)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(Color.blue.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func assistantBubble(_ turn: IntakeTurn) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ShipFirstBrain • #\(turn.turnIndex)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(turn.rawText)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func reloadAll() async {
        guard let api = appState.api else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            async let turns = api.listIntakeTurns(projectID: run.projectID, cycleNo: activeCycleNo)
            async let decisionList = api.listDecisionItems(projectID: run.projectID, cycleNo: activeCycleNo)
            async let docList = api.listLatestDocuments(projectID: run.projectID, cycleNo: activeCycleNo)
            intakeTurns = try await turns
            decisions = try await decisionList
            documents = try await docList
            let readiness = CommitReadinessEvaluator.evaluate(decisions: decisions)
            canCommit = readiness.canCommit
            if commitBlockers.isEmpty {
                commitBlockers = readiness.blockers
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendUserMessage() async {
        let text = intakeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let api = appState.api else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await api.nextTurn(
                projectID: run.projectID,
                cycleNo: activeCycleNo,
                userMessage: text,
                selectedOptionID: nil,
                noneFitText: nil
            )
            intakeInput = ""
            applyNextTurnResult(result)
            await reloadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitOption(_ option: InterviewOption) async {
        guard let api = appState.api else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let noneFitText = option.id == "none_fit"
                ? intakeInput.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
            let result = try await api.nextTurn(
                projectID: run.projectID,
                cycleNo: activeCycleNo,
                userMessage: nil,
                selectedOptionID: option.id,
                noneFitText: noneFitText,
                checkpointResponse: nil
            )
            intakeInput = ""
            applyNextTurnResult(result)
            await reloadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitCheckpointAction(checkpoint: NextTurnResult.Checkpoint, option: InterviewOption) async {
        guard let api = appState.api else { return }
        guard let action = checkpointAction(for: option.id) else {
            errorMessage = "Unknown checkpoint option selected."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let optionalText = action == "partial"
                ? intakeInput.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
            let checkpointResponse = NextTurnCheckpointResponse(
                checkpointID: checkpoint.id,
                action: action,
                optionalText: optionalText?.isEmpty == true ? nil : optionalText
            )
            let result = try await api.nextTurn(
                projectID: run.projectID,
                cycleNo: activeCycleNo,
                userMessage: nil,
                selectedOptionID: nil,
                noneFitText: nil,
                checkpointResponse: checkpointResponse
            )
            intakeInput = ""
            applyNextTurnResult(result)
            await reloadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitContract() async {
        guard let api = appState.api else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await api.commitContract(projectID: run.projectID, cycleNo: activeCycleNo)
            documents = result.documents
            if let submission = result.submission {
                submissionResult = SubmissionResult(
                    submissionID: submission.submissionID,
                    contractVersionID: result.contractVersionID,
                    bucket: submission.bucket,
                    path: submission.path,
                    submittedAt: submission.submittedAt
                )
            } else {
                submissionResult = nil
            }
            commitBlockers = []
            selectedSegment = .review
        } catch AppError.validation(let message, let issues) {
            let merged = issues.isEmpty ? [message] : issues
            commitBlockers = merged
            canCommit = false
            errorMessage = message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitBundle() async {
        guard let api = appState.api else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await api.submitRun(projectID: run.projectID, cycleNo: activeCycleNo)
            submissionResult = result
        } catch AppError.validation(let message, let issues) {
            let merged = issues.isEmpty ? [message] : issues
            commitBlockers = merged
            errorMessage = message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startNewCycle() async {
        guard let api = appState.api else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let nextCycle = try await api.startNewCycle(projectID: run.projectID, from: activeCycleNo)
            activeCycleNo = nextCycle
            intakeTurns = []
            decisions = []
            documents = []
            pendingOptions = []
            pendingCheckpoint = nil
            serverUnresolved = []
            commitBlockers = []
            canCommit = false
            intakeInput = ""
            artifactURLInput = ""
            latestArtifact = nil
            artifactStatusMessage = nil
            submissionResult = nil
            appState.draftStore.resetBlankCanvas()
            await reloadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyNextTurnResult(_ result: NextTurnResult) {
        pendingCheckpoint = result.checkpoint
        pendingOptions = result.checkpoint?.requiresResponse == true ? [] : result.options
        serverUnresolved = result.unresolved
        canCommit = result.canCommit
        commitBlockers = result.commitBlockers
        lastPostureMode = result.postureMode
        lastMoveType = result.moveType
        latestArtifact = result.artifact
        artifactStatusMessage = result.artifact?.statusMessage
    }

    private func ingestArtifactURL(forceRefresh: Bool) async {
        let url = normalizeUserURL(artifactURLInput)
        guard !url.isEmpty, let api = appState.api else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            artifactURLInput = url
            let result = try await api.nextTurn(
                projectID: run.projectID,
                cycleNo: activeCycleNo,
                userMessage: nil,
                selectedOptionID: nil,
                noneFitText: nil,
                checkpointResponse: nil,
                artifactRef: url,
                artifactType: "website",
                forceRefresh: forceRefresh
            )
            applyNextTurnResult(result)
            await reloadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func checkpointAction(for optionID: String) -> String? {
        switch optionID {
        case "checkpoint:confirm":
            return "confirm"
        case "checkpoint:reject":
            return "reject"
        case "checkpoint:partial":
            return "partial"
        case "checkpoint:skip":
            return "skip"
        default:
            return nil
        }
    }

    private func normalizeUserURL(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }
}

struct DocumentDetailView: View {
    let document: BrainDocument

    var body: some View {
        List {
            Section {
                Text(document.title)
                    .font(.headline)
                Text(document.body)
            }

            Section("Claims") {
                ForEach(document.claims.sorted(by: { $0.claimIndex < $1.claimIndex })) { claim in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(claim.claimText)
                        Text("Trust: \(claim.trustLabel.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Provenance: \(claim.provenanceRefs.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Role \(document.roleID)")
    }
}
