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
    @State private var intakeInput: String = ""
    @State private var selectedSegment: Segment = .intake
    @State private var operatingFeel: String = ""
    @State private var changePolicy: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var submissionResult: SubmissionResult?

    enum Segment: String, CaseIterable {
        case intake = "Intake"
        case review = "Review"
    }

    private let operatingFeelOptions = [
        "Safety-first",
        "Balanced",
        "Flexible",
        "Strictly guided"
    ]

    private let changePolicyOptions = [
        "Lock only after explicit confirmation",
        "Allow unknowns and revisit later",
        "Defer ambiguous areas to next cycle",
        "Stop until all critical unknowns are resolved"
    ]

    private var unknownDecisions: [DecisionItem] {
        decisions.filter { $0.status == .unknown }
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
        .navigationTitle("\(run.title) • C\(run.cycleNo)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset Draft") {
                    appState.draftStore.resetBlankCanvas()
                    intakeInput = ""
                    operatingFeel = ""
                    changePolicy = ""
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
                    Text("Open Discovery")
                        .font(.headline)
                    Text("Describe your business intent in your own words; the system captures turns before locking meaning.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(intakeTurns) { turn in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Turn #\(turn.turnIndex)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(turn.rawText)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    TextEditor(text: $intakeInput)
                        .frame(minHeight: 100)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))

                    Button("Add Intake Turn") {
                        Task { await addIntakeTurn() }
                    }
                    .disabled(intakeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Alignment Checkpoints")
                        .font(.headline)
                    Text("Constrained confirmations lock meaning and prevent silent invention.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    alignmentPicker(
                        title: "Which operating feel matches your intent best?",
                        selection: $operatingFeel,
                        options: operatingFeelOptions,
                        decisionKey: "alignment_operating_feel"
                    )

                    alignmentPicker(
                        title: "How should unresolved ambiguity be handled?",
                        selection: $changePolicy,
                        options: changePolicyOptions,
                        decisionKey: "alignment_unknown_policy"
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Unknowns")
                        .font(.headline)

                    if unknownDecisions.isEmpty {
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
                    }
                }

                Button("Generate / Refresh 10 Documents") {
                    Task { await generateDocuments() }
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
                Button("Regenerate Documents") {
                    Task { await generateDocuments() }
                }

                Button("Submit") {
                    Task { await submitRun() }
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

    private func alignmentPicker(title: String, selection: Binding<String>, options: [String], decisionKey: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
            Picker(title, selection: selection) {
                Text("Select").tag("")
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .onChange(of: selection.wrappedValue) { _, newValue in
                guard !newValue.isEmpty else { return }
                Task { await saveAlignmentDecision(key: decisionKey, value: newValue) }
            }
        }
    }

    private func reloadAll() async {
        guard let api = appState.api else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            async let turns = api.listIntakeTurns(projectID: run.projectID, cycleNo: run.cycleNo)
            async let decisionList = api.listDecisionItems(projectID: run.projectID, cycleNo: run.cycleNo)
            async let docList = api.listLatestDocuments(projectID: run.projectID, cycleNo: run.cycleNo)
            intakeTurns = try await turns
            decisions = try await decisionList
            documents = try await docList
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addIntakeTurn() async {
        let text = intakeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let api = appState.api else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let nextIndex = (intakeTurns.last?.turnIndex ?? 0) + 1
            _ = try await api.addIntakeTurn(projectID: run.projectID, cycleNo: run.cycleNo, text: text, turnIndex: nextIndex)
            intakeInput = ""
            appState.draftStore.currentDraftText = ""
            intakeTurns = try await api.listIntakeTurns(projectID: run.projectID, cycleNo: run.cycleNo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveAlignmentDecision(key: String, value: String) async {
        guard let api = appState.api else { return }

        do {
            let evidence = ["decision:\(key)", "checkpoint:mcq"]
            try await api.upsertDecisionItem(
                projectID: run.projectID,
                cycleNo: run.cycleNo,
                key: key,
                claim: value,
                status: .userSaid,
                evidenceRefs: evidence,
                lockState: .locked
            )
            decisions = try await api.listDecisionItems(projectID: run.projectID, cycleNo: run.cycleNo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func generateDocuments() async {
        guard let api = appState.api else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            documents = try await api.generateDocuments(projectID: run.projectID, cycleNo: run.cycleNo)
            decisions = try await api.listDecisionItems(projectID: run.projectID, cycleNo: run.cycleNo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitRun() async {
        guard let api = appState.api else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            submissionResult = try await api.submitRun(projectID: run.projectID, cycleNo: run.cycleNo)
            documents = try await api.listLatestDocuments(projectID: run.projectID, cycleNo: run.cycleNo)
        } catch {
            errorMessage = error.localizedDescription
        }
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
