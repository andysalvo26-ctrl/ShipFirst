import SwiftUI
import Foundation

enum KodosProductUIState: Equatable {
    case startIntake
    case continueIntake
    case readyToCommit
    case reviewDocuments
    case submissionComplete
}

enum KodosTurnTask {
    case websiteContext
    case verification(NextTurnResult.Checkpoint, NextTurnResult.ArtifactContextState?)
    case optionSelection([InterviewOption])
    case commitReview([String], Bool, InterviewOption?)
    case evidenceInput
}

struct KodosProductStateResolver {
    static func resolve(hasTurns: Bool, hasPendingCheckpoint: Bool, canCommit: Bool, hasDocs: Bool, hasSubmission: Bool) -> KodosProductUIState {
        if hasSubmission { return .submissionComplete }
        if hasDocs { return .reviewDocuments }
        if canCommit { return .readyToCommit }
        if hasTurns || hasPendingCheckpoint { return .continueIntake }
        return .startIntake
    }
}

struct KodosTurnTaskResolver {
    static func resolve(
        hasCompletedContextStep: Bool,
        pendingCheckpoint: NextTurnResult.Checkpoint?,
        artifactState: NextTurnResult.ArtifactContextState?,
        pendingOptions: [InterviewOption],
        canCommit: Bool,
        commitBlockers: [String]
    ) -> KodosTurnTask {
        if !hasCompletedContextStep {
            return .websiteContext
        }
        if let checkpoint = pendingCheckpoint, checkpoint.requiresResponse {
            return .verification(checkpoint, artifactState)
        }
        if canCommit {
            let improveOption = pendingOptions.first(where: { $0.id == "readiness:improve_quality" })
            return .commitReview(commitBlockers.map(plainEnglishBlocker), canCommit, improveOption)
        }
        if !pendingOptions.isEmpty {
            return .optionSelection(pendingOptions)
        }
        return .evidenceInput
    }
}

fileprivate func plainEnglishBlocker(_ blocker: String) -> String {
    let normalized = blocker.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = normalized.lowercased()

    if lower.contains("business_type") || lower.contains("business type") {
        return "Confirm the business type before commit."
    }
    if lower.contains("website understanding") || lower.contains("artifact") || lower.contains("verification") {
        return "Verify the website understanding before commit."
    }
    if lower.contains("contradiction") || lower.contains("conflict") {
        return "Resolve the remaining contradiction before commit."
    }
    return normalized
}

fileprivate enum KodosStageLabel {
    case idea
    case websiteContext
    case openQuestions
    case draftPacket
    case submittedPacket

    var title: String {
        switch self {
        case .idea: return "Your Idea"
        case .websiteContext: return "Website Context"
        case .openQuestions: return "Guided Setup"
        case .draftPacket: return "Draft Plan"
        case .submittedPacket: return "Submitted Plan"
        }
    }
}

fileprivate func userFacingAssistantText(_ text: String) -> String {
    var normalized = text
    let replacements: [(String, String)] = [
        ("draft packet", "draft plan"),
        ("Draft packet", "Draft plan"),
        ("commit review", "review before generating"),
        ("Commit review", "Review before generating"),
        ("commit", "generate"),
        ("Commit", "Generate"),
        ("blockers", "open items"),
        ("Blockers", "Open items")
    ]
    for (from, to) in replacements {
        normalized = normalized.replacingOccurrences(of: from, with: to)
    }
    return normalized
}

fileprivate func userFacingOptionLabel(_ option: InterviewOption) -> String {
    switch option.id {
    case "readiness:review_blockers":
        return "Review open items"
    case "readiness:ready_to_commit":
        return "Generate my draft plan"
    case "readiness:improve_quality":
        return "Answer one more setup question"
    default:
        return option.label
    }
}

fileprivate func userFacingReadinessFocus(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "Answer the next question to keep moving." }
    let lower = trimmed.lowercased()
    if lower.contains("quality signal") { return "One more setup answer to strengthen your draft." }
    if lower.contains("business type") { return "Confirm what kind of app this is." }
    if lower.contains("first customer outcome") { return "Confirm what customers should do first." }
    if lower.contains("version one capabilities") { return "Pick one or two core version-one capabilities." }
    if lower.contains("payment approach") { return "Decide whether payments are needed now or later." }
    return userFacingAssistantText(trimmed)
}

fileprivate func readinessText(_ readiness: NextTurnResult.Readiness) -> (title: String, progress: String, next: String) {
    let title = "Setup progress"
    let progress = "\(readiness.resolvedCount) of \(readiness.totalCount) core answers confirmed"
    let next = userFacingReadinessFocus(readiness.nextFocus)

    return (title, progress, next)
}

fileprivate struct LocalSetupState {
    let readiness: NextTurnResult.Readiness
    let canCommit: Bool
    let blockers: [String]
}

fileprivate func localSetupState(
    turns: [IntakeTurn],
    decisions: [DecisionItem],
    hasWebsiteContext: Bool,
    pendingCheckpoint: Bool
) -> LocalSetupState {
    let latestByKey: [String: DecisionItem] = Dictionary(grouping: decisions, by: \.decisionKey)
        .reduce(into: [:]) { partial, entry in
            if let latest = entry.value.max(by: { $0.updatedAt < $1.updatedAt }) {
                partial[entry.key] = latest
            }
        }

    func isConfirmed(_ key: String) -> Bool {
        guard let decision = latestByKey[key] else { return false }
        return decision.status == .userSaid && decision.lockState == .locked && decision.confirmedByTurnID != nil
    }

    let hasBusinessType = isConfirmed("business_type")
    let hasOutcome = isConfirmed("primary_outcome")
    let hasCapabilities = isConfirmed("launch_capabilities")
    let hasMonetization = isConfirmed("monetization_path")

    let richEvidenceCount = turns
        .filter { $0.actorType == .user }
        .map { $0.rawText.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .filter { !$0.lowercased().hasPrefix("selection:") && !$0.lowercased().hasPrefix("artifact verification:") }
        .filter { $0.split(whereSeparator: \.isWhitespace).count >= 5 }
        .count
    let qualityTarget = 3
    let qualityReady = richEvidenceCount >= qualityTarget
    let unresolvedConflicts = decisions.filter(\.hasConflict).count

    let buckets: [NextTurnResult.ReadinessBucket] = [
        .init(key: "business_type", label: "Business type", status: hasBusinessType ? "resolved" : "missing", detail: hasBusinessType ? "Locked." : "Confirm what kind of app this is."),
        .init(key: "primary_outcome", label: "First customer outcome", status: hasOutcome ? "resolved" : "missing", detail: hasOutcome ? "Locked." : "Define what users should do first."),
        .init(key: "launch_capabilities", label: "Version one capabilities", status: hasCapabilities ? "resolved" : "missing", detail: hasCapabilities ? "Locked." : "Choose one or two core capabilities."),
        .init(key: "monetization_path", label: "Payment approach", status: hasMonetization ? "resolved" : "missing", detail: hasMonetization ? "Locked." : "Decide payment now vs later."),
        .init(key: "quality_signal", label: "Draft quality signal", status: qualityReady ? "resolved" : "missing", detail: qualityReady ? "Enough plain-language detail captured." : "Answer \(max(1, qualityTarget - richEvidenceCount)) more easy setup question(s)."),
        .init(key: "context_step", label: "Setup context", status: hasWebsiteContext || !turns.isEmpty ? "resolved" : "missing", detail: hasWebsiteContext ? "Website context linked." : "Idea captured."),
    ]

    let resolvedCount = buckets.filter { $0.status == "resolved" }.count
    let totalCount = buckets.count
    let score = Int((Double(resolvedCount) / Double(max(1, totalCount))) * 100.0)
    let nextFocus = buckets.first(where: { $0.status != "resolved" })?.label ?? "Ready for draft review"
    let readiness = NextTurnResult.Readiness(
        score: score,
        resolvedCount: resolvedCount,
        totalCount: totalCount,
        nextFocus: nextFocus,
        buckets: buckets
    )

    var blockers: [String] = []
    if !hasBusinessType { blockers.append("Confirm your app type.") }
    if !hasOutcome { blockers.append("Confirm what users should do first.") }
    if !hasCapabilities { blockers.append("Choose one or two version-one capabilities.") }
    if !hasMonetization { blockers.append("Decide whether payments are needed in version one.") }
    if !qualityReady { blockers.append("Add \(max(1, qualityTarget - richEvidenceCount)) more plain-language setup answer(s) so the draft is strong enough.") }
    if pendingCheckpoint { blockers.append("Finish the current confirmation before generating.") }
    if unresolvedConflicts > 0 { blockers.append("Resolve \(unresolvedConflicts) contradiction(s).") }

    let canCommit = blockers.isEmpty
    return LocalSetupState(readiness: readiness, canCommit: canCommit, blockers: blockers)
}

fileprivate struct KodosSurface<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground).opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    content()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

fileprivate struct KodosCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

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
                KodosWelcomeAuthView()
            } else {
                KodosProjectHomeView()
            }
        }
    }
}

struct KodosWelcomeAuthView: View {
    @EnvironmentObject private var appState: AppState

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSignInMode: Bool = true
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            KodosSurface(
                title: "ShipFirst Kodos",
                subtitle: "Set up your app idea and produce a trusted draft packet."
            ) {
                KodosCard {
                    TextField("Email", text: $email)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .padding(12)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    SecureField("Password", text: $password)
                        .padding(12)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button {
                        Task { await authenticate() }
                    } label: {
                        Text(isSignInMode ? "Continue" : "Create Account")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)

                    Button(isSignInMode ? "Need an account? Sign up" : "Have an account? Sign in") {
                        isSignInMode.toggle()
                        errorMessage = nil
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
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

private struct ProjectBucket: Identifiable {
    let id: UUID
    let title: String
    let latestCycle: Int
    let latestStatus: String
    let latestUpdatedAt: String
}

private struct ProjectRoute: Identifiable, Hashable {
    let id: UUID
    let title: String
}

struct KodosProjectHomeView: View {
    @EnvironmentObject private var appState: AppState

    @State private var runs: [RunSummary] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var routeToProject: ProjectRoute?

    private var projects: [ProjectBucket] {
        Dictionary(grouping: runs, by: \ .projectID)
            .map { key, groupedRuns in
                let sorted = groupedRuns.sorted { $0.cycleNo > $1.cycleNo }
                return ProjectBucket(
                    id: key,
                    title: sorted.first?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? (sorted.first?.title ?? "Untitled Project") : "Untitled Project",
                    latestCycle: sorted.first?.cycleNo ?? 1,
                    latestStatus: sorted.first?.status ?? "draft",
                    latestUpdatedAt: sorted.first?.updatedAt ?? sorted.first?.createdAt ?? ""
                )
            }
            .sorted { $0.latestUpdatedAt > $1.latestUpdatedAt }
    }

    var body: some View {
        NavigationStack {
            KodosSurface(
                title: "Kodos",
                subtitle: "Choose a project or start a new one."
            ) {
                KodosCard {
                    Button {
                        Task { await createProject() }
                    } label: {
                        Text("Start New Project")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                KodosCard {
                    Text("Projects")
                        .font(.headline)
                    if projects.isEmpty && !isLoading {
                        Text("No projects yet.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(projects) { project in
                        NavigationLink {
                            KodosProjectRunsView(projectID: project.id, projectTitle: project.title)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(project.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("Latest run: \(project.latestStatus.capitalized), cycle \(project.latestCycle)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $routeToProject) { route in
                KodosProjectRunsView(projectID: route.id, projectTitle: route.title)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign Out") { appState.signOut() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") { Task { await loadRuns() } }
                }
            }
            .overlay {
                if isLoading { ProgressView() }
            }
            .task { await loadRuns() }
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

    private func createProject() async {
        guard let api = appState.api else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let createdRun = try await api.createRun()
            routeToProject = ProjectRoute(id: createdRun.projectID, title: createdRun.title)
            do {
                runs = try await api.listRuns()
            } catch {
                // Keep forward momentum: navigation to the newly created project should not be blocked by refresh errors.
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct KodosProjectRunsView: View {
    @EnvironmentObject private var appState: AppState

    let projectID: UUID
    let projectTitle: String

    @State private var runs: [RunSummary] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var routeToRun: RunSummary?

    private var projectRuns: [RunSummary] {
        runs
            .filter { $0.projectID == projectID }
            .sorted { $0.cycleNo > $1.cycleNo }
    }

    var body: some View {
        KodosSurface(
            title: safeTitle(projectTitle),
            subtitle: "Each run gets its own draft packet cycle."
        ) {
            KodosCard {
                Button {
                    Task { await startNewRun() }
                } label: {
                    Text("Start New Run")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            KodosCard {
                Text("Runs")
                    .font(.headline)
                if projectRuns.isEmpty && !isLoading {
                    Text("No runs yet.")
                        .foregroundStyle(.secondary)
                }

                ForEach(projectRuns) { run in
                    NavigationLink {
                        KodosRunHomeView(run: run, projectTitle: projectTitle)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cycle \(run.cycleNo)")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(run.status.capitalized)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $routeToRun) { run in
            KodosRunHomeView(run: run, projectTitle: projectTitle)
        }
        .overlay {
            if isLoading { ProgressView() }
        }
        .task { await loadRuns() }
        .refreshable { await loadRuns() }
        .alert("Error", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
            Button("OK") { errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private func safeTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Project" : trimmed
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

    private func startNewRun() async {
        guard let api = appState.api else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let current = projectRuns.first?.cycleNo ?? 0
            let nextCycle = try await api.startNewCycle(projectID: projectID, from: current)
            let now = ISO8601DateFormatter().string(from: Date())
            routeToRun = RunSummary(
                projectID: projectID,
                cycleNo: nextCycle,
                title: projectTitle,
                status: "draft",
                latestContractVersionID: nil,
                latestSubmissionPath: nil,
                createdAt: now,
                updatedAt: now,
                submittedAt: nil
            )

            do {
                runs = try await api.listRuns()
                if let started = runs.first(where: { $0.projectID == projectID && $0.cycleNo == nextCycle }) {
                    routeToRun = started
                }
            } catch {
                // Keep forward momentum: a successful cycle start should still open the run.
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct KodosRunHomeView: View {
    @EnvironmentObject private var appState: AppState

    let run: RunSummary
    let projectTitle: String

    @State private var intakeTurns: [IntakeTurn] = []
    @State private var decisions: [DecisionItem] = []
    @State private var documents: [BrainDocument] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showTurnLoop: Bool = false
    @State private var showCommitReview: Bool = false
    @State private var showDocsReview: Bool = false

    private var homeSetupState: LocalSetupState {
        localSetupState(
            turns: intakeTurns,
            decisions: decisions,
            hasWebsiteContext: intakeTurns.contains(where: { $0.rawText.lowercased().contains("http://") || $0.rawText.lowercased().contains("https://") }),
            pendingCheckpoint: hasPendingCheckpoint
        )
    }

    private var plainBlockers: [String] {
        homeSetupState.blockers.map(plainEnglishBlocker)
    }

    private var hasPendingCheckpoint: Bool {
        decisions.contains { $0.decisionKey == "artifact_verification" && $0.status == .unknown }
    }

    private var state: KodosProductUIState {
        KodosProductStateResolver.resolve(
            hasTurns: !intakeTurns.isEmpty,
            hasPendingCheckpoint: hasPendingCheckpoint,
            canCommit: homeSetupState.canCommit,
            hasDocs: !documents.isEmpty,
            hasSubmission: run.latestSubmissionPath != nil
        )
    }

    private var primaryActionTitle: String {
        switch state {
        case .startIntake: return "Start setup"
        case .continueIntake: return "Continue setup"
        case .readyToCommit: return "Review and generate 10 docs"
        case .reviewDocuments: return "Review your 10 docs"
        case .submissionComplete: return "View submitted handoff"
        }
    }

    private var stageLabel: KodosStageLabel {
        switch state {
        case .startIntake:
            return .idea
        case .continueIntake:
            return hasPendingCheckpoint ? .openQuestions : .openQuestions
        case .readyToCommit, .reviewDocuments:
            return .draftPacket
        case .submissionComplete:
            return .submittedPacket
        }
    }

    var body: some View {
        KodosSurface(
            title: safeTitle(projectTitle),
            subtitle: "\(stageLabel.title) • Cycle \(run.cycleNo)"
        ) {
            KodosCard {
                Text(stateSummary)
                    .font(.body)
                    .foregroundStyle(.secondary)

                Button(primaryActionTitle) {
                    handlePrimaryAction()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                Button("Refresh") {
                    Task { await reload() }
                }
                .buttonStyle(.bordered)
            }

            if !plainBlockers.isEmpty && state != .submissionComplete {
                KodosCard {
                    Text("Open questions to resolve")
                        .font(.headline)
                    ForEach(plainBlockers, id: \.self) { blocker in
                        Text("• \(blocker)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading { ProgressView() }
        }
        .task { await reload() }
        .sheet(isPresented: $showTurnLoop) {
            KodosTurnLoopView(run: run, projectTitle: projectTitle)
                .environmentObject(appState)
        }
                .sheet(isPresented: $showCommitReview) {
            KodosCommitReviewView(
                projectID: run.projectID,
                cycleNo: run.cycleNo,
                canCommit: homeSetupState.canCommit,
                blockers: plainBlockers,
                onCommitted: { _ in
                    showCommitReview = false
                    showDocsReview = true
                    Task { await reload() }
                },
                onCommitBlocked: { _ in
                    Task { await reload() }
                }
            )
            .environmentObject(appState)
        }
        .sheet(isPresented: $showDocsReview) {
            KodosDocumentsReviewView(
                projectID: run.projectID,
                cycleNo: run.cycleNo,
                initialDocuments: documents,
                isSubmissionLocked: run.latestSubmissionPath != nil,
                existingSubmissionPath: run.latestSubmissionPath,
                existingSubmittedAt: run.submittedAt
            )
            .environmentObject(appState)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
            Button("OK") { errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private var stateSummary: String {
        switch state {
        case .startIntake:
            return "Start by sharing your idea."
        case .continueIntake:
            return "Answer one setup question at a time."
        case .readyToCommit:
            return "You have enough signal to generate your first 10-document draft."
        case .reviewDocuments:
            return "Your 10-document draft is ready for review."
        case .submissionComplete:
            return "Your handoff bundle has been submitted."
        }
    }

    private func handlePrimaryAction() {
        switch state {
        case .startIntake, .continueIntake:
            showTurnLoop = true
        case .readyToCommit:
            showCommitReview = true
        case .reviewDocuments, .submissionComplete:
            showDocsReview = true
        }
    }

    private func reload() async {
        guard let api = appState.api else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            async let turns = api.listIntakeTurns(projectID: run.projectID, cycleNo: run.cycleNo)
            async let decisionRows = api.listDecisionItems(projectID: run.projectID, cycleNo: run.cycleNo)
            async let docs = api.listLatestDocuments(projectID: run.projectID, cycleNo: run.cycleNo)
            intakeTurns = try await turns
            decisions = try await decisionRows
            documents = try await docs
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func safeTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New Project" }
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("project ") && trimmed.contains("T") && trimmed.hasSuffix("Z") {
            return "New Project"
        }
        return trimmed
    }
}

struct KodosTurnLoopView: View {
    @EnvironmentObject private var appState: AppState

    let run: RunSummary
    let projectTitle: String

    @State private var activeCycleNo: Int
    @State private var intakeTurns: [IntakeTurn] = []
    @State private var decisions: [DecisionItem] = []
    @State private var hasCompletedContextStep: Bool = false
    @State private var textInput: String = ""
    @State private var websiteInput: String = ""
    @State private var pendingOptions: [InterviewOption] = []
    @State private var pendingCheckpoint: NextTurnResult.Checkpoint?
    @State private var selectedOptionsDraft: [InterviewOption] = []
    @State private var checkpointCorrectionText: String = ""
    @State private var unresolved: [UnresolvedDecision] = []
    @State private var readiness: NextTurnResult.Readiness?
    @State private var canCommit: Bool = false
    @State private var commitBlockers: [String] = []
    @State private var lastPosture: PostureMode?
    @State private var lastMove: MoveType?
    @State private var artifactState: NextTurnResult.ArtifactContextState?
    @State private var currentPromptText: String = ""
    @State private var actionStatusMessage: String?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showCommitReview: Bool = false
    @State private var showDocsReview: Bool = false
    @State private var committedResult: CommitContractResult?
#if DEBUG
    @State private var showDebugPanel: Bool = false
#endif

    init(run: RunSummary, projectTitle: String) {
        self.run = run
        self.projectTitle = projectTitle
        _activeCycleNo = State(initialValue: run.cycleNo)
    }

    private var displayedTurns: [IntakeTurn] {
        intakeTurns.filter {
            let text = $0.rawText.lowercased()
            guard !text.hasPrefix("selection:") else { return false }
            guard !text.hasPrefix("artifact verification:") else { return false }
            guard !text.contains("resolve the pending checkpoint") else { return false }
            guard !text.contains("what specific artifact") else { return false }
            guard !text.contains("specific artifacts") else { return false }
            guard !text.contains("artifact verification") else { return false }
            return true
        }
    }

    private var nextStepText: String {
        let prompt = currentPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch currentTask {
        case .websiteContext:
            return "Share your app idea, then optionally add your website for context."
        case .verification(_, let artifact):
            if !prompt.isEmpty { return prompt }
            if let summary = artifact?.summaryText, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Review the website summary below and confirm or correct it."
            }
            return "Confirm or correct the website context so we can continue."
        case .optionSelection:
            if !prompt.isEmpty { return prompt }
            if let readiness {
                let focus = userFacingReadinessFocus(readiness.nextFocus)
                if !focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return focus
                }
            }
            return "Pick one option below so we can keep moving."
        case .commitReview(let blockers, let canCommit, _):
            if !prompt.isEmpty { return prompt }
            if canCommit {
                return "You're ready to generate your draft plan."
            }
            if let first = blockers.first {
                return plainEnglishBlocker(first)
            }
            return "Resolve the open items before generating."
        case .evidenceInput:
            if !prompt.isEmpty { return prompt }
            return guidedQuestionFromReadiness ?? "Add one concrete detail in your own words."
        }
    }

    private var guidedQuestionFromReadiness: String? {
        guard let readiness else { return nil }
        guard !canCommit else { return nil }
        if pendingCheckpoint?.requiresResponse == true { return nil }

        if let missing = readiness.buckets.first(where: { $0.status != "resolved" })?.key {
            switch missing {
            case "business_type":
                return "What kind of app are you creating (for example: booking, selling, portfolio, or something else)?"
            case "primary_outcome":
                return "What should customers do first when they open your app?"
            case "launch_capabilities":
                return "For version one, pick one or two features that matter most."
            case "monetization_path":
                return "Do you want payments in version one, or later?"
            case "quality_signal":
                return "Share one more concrete detail so we can make your first draft stronger."
            default:
                return "Answer the next simple setup question and we’ll keep moving."
            }
        }
        return nil
    }

    private var currentTask: KodosTurnTask {
        KodosTurnTaskResolver.resolve(
            hasCompletedContextStep: hasCompletedContextStep,
            pendingCheckpoint: pendingCheckpoint,
            artifactState: artifactState,
            pendingOptions: pendingOptions,
            canCommit: canCommit,
            commitBlockers: commitBlockers
        )
    }

    private var turnStage: KodosStageLabel {
        switch currentTask {
        case .websiteContext:
            return .websiteContext
        case .verification, .optionSelection, .evidenceInput:
            return .openQuestions
        case .commitReview:
            return .draftPacket
        }
    }

    private var turnTaskHeadline: String {
        switch currentTask {
        case .websiteContext:
            return "Start with your idea"
        case .verification:
            return "Confirm understanding"
        case .optionSelection:
            return "Choose what fits best"
        case .commitReview(_, _, let improveOption):
            return improveOption == nil
                ? "Your draft plan is ready to generate"
                : "You can generate now or improve once more"
        case .evidenceInput:
            return "Add one detail in your own words"
        }
    }

    var body: some View {
        KodosSurface(
            title: safeTitle(projectTitle),
            subtitle: "\(turnStage.title) • Cycle \(activeCycleNo)"
        ) {
            if let readiness {
                let copy = readinessText(readiness)
                HStack(spacing: 10) {
                    ProgressView(value: Double(readiness.score), total: 100)
                        .frame(width: 96)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy.progress)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 2)
            }

            KodosCard {
                Text(nextStepText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
                if let actionStatusMessage {
                    Text(actionStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                    .padding(.vertical, 2)
                TurnRenderer(
                    task: currentTask,
                    selectedOptions: $selectedOptionsDraft,
                    correctionText: $checkpointCorrectionText,
                    textInput: $textInput,
                    websiteInput: $websiteInput,
                    allowTwoSelections: allowsDualSelection,
                    isLoading: isLoading,
                    onStartWithWebsite: {
                        Task { await startInterviewFlow(withWebsite: true) }
                    },
                    onStartWithoutWebsite: {
                        Task { await startInterviewFlow(withWebsite: false) }
                    },
                    onSelectOption: { option in
                        toggleOptionSelection(option)
                    },
                    onQuickSelectOption: { option in
                        Task { await quickSelectOption(option) }
                    },
                    onContinueOptionSelection: {
                        guard !selectedOptionsDraft.isEmpty else {
                            errorMessage = "Select an option to continue."
                            return
                        }
                        Task { await continueOptionSelection() }
                    },
                    onCheckpointAction: { checkpoint, action in
                        Task { await handleCheckpointAction(checkpoint: checkpoint, action: action) }
                    },
                    onCommitTapped: {
                        showCommitReview = true
                    },
                    onImproveDraft: { option in
                        Task { await runQualityBoost(option: option) }
                    },
                    onSendEvidence: {
                        Task { await sendEvidence() }
                    }
                )
            }

#if DEBUG
            if showDebugPanel {
                KodosCard {
                    Text("Debug")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("posture: \(lastPosture?.rawValue ?? "-")")
                        Text("move: \(lastMove?.rawValue ?? "-")")
                        Text("unresolved: \(unresolved.count)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
#endif
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Blank Canvas") {
                    Task { await blankCanvas() }
                }
            }
#if DEBUG
            ToolbarItem(placement: .topBarTrailing) {
                Button(showDebugPanel ? "Hide Debug" : "Debug") {
                    showDebugPanel.toggle()
                }
            }
#endif
        }
        .overlay {
            if isLoading { ProgressView() }
        }
        .task { await reloadState() }
        .sheet(isPresented: $showCommitReview) {
            KodosCommitReviewView(
                projectID: run.projectID,
                cycleNo: activeCycleNo,
                canCommit: canCommit,
                blockers: commitBlockers.map(plainEnglishBlocker),
                onCommitted: { result in
                    committedResult = result
                    showCommitReview = false
                    showDocsReview = true
                },
                onCommitBlocked: { blockers in
                    commitBlockers = blockers
                    canCommit = false
                }
            )
            .environmentObject(appState)
        }
        .sheet(isPresented: $showDocsReview) {
            KodosDocumentsReviewView(
                projectID: run.projectID,
                cycleNo: activeCycleNo,
                initialDocuments: committedResult?.documents,
                isSubmissionLocked: false,
                existingSubmissionPath: nil,
                existingSubmittedAt: nil
            )
            .environmentObject(appState)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
            Button("OK") { errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private func reloadState() async {
        guard let api = appState.api else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            async let turns = api.listIntakeTurns(projectID: run.projectID, cycleNo: activeCycleNo)
            async let decisionRows = api.listDecisionItems(projectID: run.projectID, cycleNo: activeCycleNo)
            intakeTurns = try await turns
            decisions = try await decisionRows
            if let latestSystemTurn = intakeTurns.last(where: { $0.actorType == .system }) {
                currentPromptText = userFacingTurnText(latestSystemTurn)
            }
            hasCompletedContextStep = shouldMarkContextComplete(turns: intakeTurns, decisions: decisions)
            let local = localSetupState(
                turns: intakeTurns,
                decisions: decisions,
                hasWebsiteContext: artifactState != nil || hasCompletedContextStep,
                pendingCheckpoint: pendingCheckpoint?.requiresResponse == true
            )
            self.readiness = local.readiness
            canCommit = local.canCommit
            commitBlockers = local.blockers
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyTurnResult(_ result: NextTurnResult) {
        pendingCheckpoint = result.checkpoint
        selectedOptionsDraft = []
        unresolved = result.unresolved
        lastPosture = result.postureMode
        lastMove = result.moveType
        currentPromptText = userFacingAssistantText(result.assistantMessage)
        artifactState = result.artifact
        if result.artifact != nil || result.checkpoint?.type.lowercased().contains("artifact") == true {
            hasCompletedContextStep = true
        }

        let local = localSetupState(
            turns: intakeTurns,
            decisions: decisions,
            hasWebsiteContext: result.artifact != nil || hasCompletedContextStep,
            pendingCheckpoint: result.checkpoint?.requiresResponse == true
        )
        readiness = local.readiness
        canCommit = result.canCommit && local.canCommit
        commitBlockers = Array(Set(result.commitBlockers + local.blockers))

        if result.checkpoint?.requiresResponse == true {
            pendingOptions = []
        } else {
            let filtered = filterUserOptions(result.options, canCommit: canCommit)
            pendingOptions = filtered
        }
    }

    private func sendEvidence() async {
        guard let api = appState.api else { return }
        let text = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = "Enter evidence to continue."
            return
        }

        isLoading = true
        actionStatusMessage = "Saving your answer..."
        defer { isLoading = false }

        do {
            let outcome = try await api.performTypedAction(projectID: run.projectID, cycleNo: activeCycleNo, action: .addEvidence(text: text))
            if case .turn(let result) = outcome {
                textInput = ""
                applyTurnResult(result)
                await reloadState()
                actionStatusMessage = "Saved. Loading next question..."
            }
        } catch {
            actionStatusMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func continueOptionSelection() async {
        guard !selectedOptionsDraft.isEmpty else {
            errorMessage = "Select an option to continue."
            return
        }
        await submitSelectedOptions(selectedOptionsDraft)
    }

    private func quickSelectOption(_ option: InterviewOption) async {
        if option.id == "none_fit" { return }
        selectedOptionsDraft = [option]
        await submitSelectedOptions([option])
    }

    private func submitSelectedOptions(_ selected: [InterviewOption]) async {
        guard let api = appState.api else { return }
        guard !selected.isEmpty else {
            errorMessage = "Select an option to continue."
            return
        }
        if selected.count > 2 {
            errorMessage = "Pick up to two options."
            return
        }

        if selected.count == 2 {
            let hasNoneFit = selected.contains { $0.id == "none_fit" }
            if hasNoneFit {
                errorMessage = "Choose either a custom answer or up to two listed options."
                return
            }
            let evaluation = evaluatePairComplexity(selected)
            if !evaluation.isAllowed {
                errorMessage = evaluation.message
                return
            }
        }

        let primary = selected[0]
        let selectedID = primary.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedID.isEmpty else {
            errorMessage = "Select an option to continue."
            return
        }

        isLoading = true
        actionStatusMessage = "Saving your choice..."
        defer { isLoading = false }

        do {
            let previousOptionIDs = pendingOptions.map(\.id)
            let previousCheckpointID = pendingCheckpoint?.id
            let previousCanCommit = canCommit
            let noneFit: String?
            if selectedID == "none_fit" {
                noneFit = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if selected.count == 2 {
                let secondary = selected[1]
                noneFit = "Secondary priority: \(plainOptionLabel(secondary.label))."
            } else {
                // Always include plain-language context so the backend can disambiguate terse option IDs.
                noneFit = "Selected option: \(plainOptionLabel(primary.label))."
            }
            let outcome = try await api.performTypedAction(projectID: run.projectID, cycleNo: activeCycleNo, action: .selectOption(id: selectedID, noneFitText: noneFit))
            if case .turn(let result) = outcome {
                textInput = ""
                selectedOptionsDraft = []
                applyTurnResult(result)
                await reloadState()
                actionStatusMessage = "Saved. Loading next question..."

                // If selection produced no visible state transition, send a tiny evidence bridge so the run advances.
                let noOptionDelta = pendingOptions.map(\.id) == previousOptionIDs
                let sameCheckpoint = pendingCheckpoint?.id == previousCheckpointID
                let noCommitDelta = canCommit == previousCanCommit
                if noOptionDelta && sameCheckpoint && noCommitDelta && pendingCheckpoint == nil {
                    let bridge = "I choose: \(plainOptionLabel(primary.label))."
                    let bridgeOutcome = try await api.performTypedAction(projectID: run.projectID, cycleNo: activeCycleNo, action: .addEvidence(text: bridge))
                    if case .turn(let bridgedResult) = bridgeOutcome {
                        applyTurnResult(bridgedResult)
                        await reloadState()
                        actionStatusMessage = "Saved. Loading next question..."
                    }
                }
            }
        } catch {
            actionStatusMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func handleCheckpointAction(checkpoint: NextTurnResult.Checkpoint, action: String) async {
        if (action == "partial" || action == "reject") && checkpointCorrectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Add a short correction before continuing."
            return
        }

        guard let api = appState.api else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let outcome: TypedActionOutcome
            switch action {
            case "confirm":
                outcome = try await api.performTypedAction(
                    projectID: run.projectID,
                    cycleNo: activeCycleNo,
                    action: .respondCheckpoint(id: checkpoint.id, action: "confirm", optionalText: nil)
                )
            case "partial":
                outcome = try await api.performTypedAction(
                    projectID: run.projectID,
                    cycleNo: activeCycleNo,
                    action: .correctArtifactUnderstanding(id: checkpoint.id, text: checkpointCorrectionText.trimmingCharacters(in: .whitespacesAndNewlines))
                )
            case "reject":
                outcome = try await api.performTypedAction(
                    projectID: run.projectID,
                    cycleNo: activeCycleNo,
                    action: .respondCheckpoint(id: checkpoint.id, action: "reject", optionalText: checkpointCorrectionText.trimmingCharacters(in: .whitespacesAndNewlines))
                )
            default:
                errorMessage = "Unknown checkpoint action."
                return
            }

            if case .turn(let result) = outcome {
                checkpointCorrectionText = ""
                textInput = ""
                applyTurnResult(result)
                await reloadState()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runQualityBoost(option: InterviewOption) async {
        guard let api = appState.api else { return }
        let selectedID = option.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedID.isEmpty else {
            errorMessage = "Could not start quality boost step."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let outcome = try await api.performTypedAction(
                projectID: run.projectID,
                cycleNo: activeCycleNo,
                action: .selectOption(id: selectedID, noneFitText: nil)
            )
            if case .turn(let result) = outcome {
                applyTurnResult(result)
                await reloadState()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startInterviewFlow(withWebsite: Bool) async {
        guard let api = appState.api else { return }
        let idea = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty else {
            errorMessage = "Share your app idea first."
            return
        }

        let artifactRef = withWebsite ? normalizeURL(websiteInput) : ""
        if withWebsite && artifactRef.isEmpty {
            errorMessage = "Add a valid website URL or choose Skip Website."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await api.nextTurn(
                projectID: run.projectID,
                cycleNo: activeCycleNo,
                userMessage: idea,
                selectedOptionID: nil,
                noneFitText: nil,
                checkpointResponse: nil,
                artifactRef: withWebsite ? artifactRef : nil,
                artifactType: withWebsite ? "website" : nil,
                forceRefresh: false
            )
            websiteInput = artifactRef
            textInput = ""
            hasCompletedContextStep = true
            applyTurnResult(result)
            await reloadState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func readWebsite() async {
        guard let api = appState.api else { return }
        let normalized = normalizeURL(websiteInput)
        guard !normalized.isEmpty else {
            errorMessage = "Enter a valid website URL."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            websiteInput = normalized
            let result = try await api.nextTurn(
                projectID: run.projectID,
                cycleNo: activeCycleNo,
                userMessage: nil,
                selectedOptionID: nil,
                noneFitText: nil,
                checkpointResponse: nil,
                artifactRef: normalized,
                artifactType: "website",
                forceRefresh: false
            )
            applyTurnResult(result)
            await reloadState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func blankCanvas() async {
        guard let api = appState.api else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let next = try await api.startNewCycle(projectID: run.projectID, from: activeCycleNo)
            activeCycleNo = next
            intakeTurns = []
            decisions = []
            pendingOptions = []
            pendingCheckpoint = nil
            unresolved = []
            canCommit = false
            commitBlockers = []
            selectedOptionsDraft = []
            checkpointCorrectionText = ""
            textInput = ""
            websiteInput = ""
            artifactState = nil
            committedResult = nil
            hasCompletedContextStep = false
            await reloadState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func normalizeURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    private func safeTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New Project" }
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("project ") && trimmed.contains("T") && trimmed.hasSuffix("Z") {
            return "New Project"
        }
        return trimmed
    }

    private var allowsDualSelection: Bool {
        guard case .optionSelection = currentTask else { return false }
        return pendingOptions.contains(where: { $0.id.hasPrefix("capability:") })
    }

    private func toggleOptionSelection(_ option: InterviewOption) {
        if let index = selectedOptionsDraft.firstIndex(where: { $0.id == option.id }) {
            selectedOptionsDraft.remove(at: index)
            return
        }
        let maxSelection = allowsDualSelection ? 2 : 1
        if selectedOptionsDraft.count >= maxSelection {
            if maxSelection == 1 {
                selectedOptionsDraft = [option]
                return
            }
            errorMessage = "For this step, choose up to two options."
            return
        }
        selectedOptionsDraft.append(option)
    }

    private func evaluatePairComplexity(_ options: [InterviewOption]) -> (isAllowed: Bool, message: String) {
        let joined = options.map { plainOptionLabel($0.label).lowercased() }.joined(separator: " ")
        let complexityKeywords = ["marketplace", "chat", "messaging", "community", "social", "stream", "ai", "live"]
        let complexityScore = complexityKeywords.reduce(into: 0) { partialResult, keyword in
            if joined.contains(keyword) { partialResult += 1 }
        }
        if complexityScore >= 2 {
            return (false, "Great ideas. For your first version, choose one now and we’ll add the second next.")
        }
        return (true, "")
    }

    private func plainOptionLabel(_ label: String) -> String {
        var value = label.replacingOccurrences(of: "_", with: " ")
        value = value.replacingOccurrences(of: "-", with: " ")
        value = value.replacingOccurrences(of: "  ", with: " ")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func userFacingTurnText(_ turn: IntakeTurn) -> String {
        guard turn.actorType == .system else { return turn.rawText }
        var text = sanitizeSystemText(turn.rawText)
        if text.lowercased().contains("specific website context") || text.lowercased().contains("specific artifacts") {
            text = "Please review the website context card below and confirm or correct it."
        }
        if text.lowercased().contains("resolve the pending checkpoint") {
            text = "Please complete the current confirmation card to continue."
        }
        if text.lowercased().contains("what features do you envision") {
            text = "Great start. Which option below feels most important for your first version?"
        }
        if text.lowercased().contains("what specific features") || text.lowercased().contains("functionalities") {
            text = "Which features matter most for your first version?"
        }
        if text.lowercased().contains("next step after finalizing") {
            text = "Before we generate your draft plan, let’s lock one more important detail."
        }
        if text.lowercased().contains("could you clarify what you mean by") && text.lowercased().contains("selection:") {
            text = "Quick check: tell me what you mean in plain words so I can lock this correctly."
        }
        return text
    }

    private func filterUserOptions(_ options: [InterviewOption], canCommit: Bool) -> [InterviewOption] {
        guard !options.isEmpty else { return [] }
        if canCommit {
            return options
        }
        return options.filter { !$0.id.hasPrefix("readiness:") }
    }

    private func sanitizeSystemText(_ raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(of: "artifact verification", with: "website context check", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "artifact", with: "website context", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "checkpoint", with: "confirmation", options: .caseInsensitive)

        let patterns: [String] = [
            "(?i)'?\\bselection\\s*:\\s*\\d+\\b'?",
            "(?i)'?\\bselection\\s*:[^'\\s]+\\b'?",
            "(?i)\\bsection\\s*\\d+\\b",
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..., in: text)
                let replacement = pattern.contains("section") ? "this part" : "that choice"
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
            }
        }

        text = text.replacingOccurrences(of: "  ", with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldMarkContextComplete(turns: [IntakeTurn], decisions: [DecisionItem]) -> Bool {
        if decisions.contains(where: { $0.decisionKey.lowercased().contains("artifact") }) {
            return true
        }
        if turns.contains(where: { $0.rawText.lowercased().contains("http://") || $0.rawText.lowercased().contains("https://") }) {
            return true
        }
        return !turns.isEmpty
    }

}

private struct TurnRenderer: View {
    let task: KodosTurnTask
    @Binding var selectedOptions: [InterviewOption]
    @Binding var correctionText: String
    @Binding var textInput: String
    @Binding var websiteInput: String
    let allowTwoSelections: Bool
    let isLoading: Bool
    let onStartWithWebsite: () -> Void
    let onStartWithoutWebsite: () -> Void
    let onSelectOption: (InterviewOption) -> Void
    let onQuickSelectOption: (InterviewOption) -> Void
    let onContinueOptionSelection: () -> Void
    let onCheckpointAction: (NextTurnResult.Checkpoint, String) -> Void
    let onCommitTapped: () -> Void
    let onImproveDraft: (InterviewOption) -> Void
    let onSendEvidence: () -> Void

    var body: some View {
        switch task {
        case .websiteContext:
            WebsiteContextStepView(
                ideaInput: $textInput,
                websiteInput: $websiteInput,
                isLoading: isLoading,
                onStartWithWebsite: onStartWithWebsite,
                onStartWithoutWebsite: onStartWithoutWebsite
            )
        case .verification(let checkpoint, let artifact):
            VerificationCheckpointView(
                checkpoint: checkpoint,
                artifact: artifact,
                correctionText: $correctionText,
                isLoading: isLoading,
                onAction: { action in onCheckpointAction(checkpoint, action) }
            )
        case .optionSelection(let options):
            OptionSelectView(
                options: options,
                selectedOptions: $selectedOptions,
                textInput: $textInput,
                allowTwoSelections: allowTwoSelections,
                isLoading: isLoading,
                onSelect: onSelectOption,
                onQuickSelect: onQuickSelectOption,
                onContinue: onContinueOptionSelection
            )
        case .commitReview(let blockers, let canCommit, let improveOption):
            CommitReviewCardView(
                blockers: blockers,
                canCommit: canCommit,
                improveOption: improveOption,
                onCommitTapped: onCommitTapped,
                onImproveTapped: onImproveDraft
            )
        case .evidenceInput:
            EvidenceInputView(
                textInput: $textInput,
                isLoading: isLoading,
                onSendEvidence: onSendEvidence
            )
        }
    }
}

private struct VerificationCheckpointView: View {
    let checkpoint: NextTurnResult.Checkpoint
    let artifact: NextTurnResult.ArtifactContextState?
    @Binding var correctionText: String
    let isLoading: Bool
    let onAction: (String) -> Void

    private var artifactTitle: String {
        guard let ref = artifact?.artifactRef, !ref.isEmpty else { return "Website context" }
        return ref
    }

    private var displayPrompt: String {
        let prompt = checkpoint.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt.isEmpty { return "Please confirm whether this summary matches your website." }
        let lowered = prompt.lowercased()
        if lowered.contains("specific artifact") || lowered.contains("specific artifacts") {
            return "Please confirm whether this summary matches your website."
        }
        return prompt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Do we have your website context right?")
                .font(.headline)
            Text(artifactTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let summary = artifact?.summaryText, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
            } else {
                Text(displayPrompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextField("If needed, add a short correction", text: $correctionText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Looks right") { onAction("confirm") }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                Button("Needs a tweak") { onAction("partial") }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
                Button("Wrong") { onAction("reject") }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
            }
        }
    }
}

private struct OptionSelectView: View {
    let options: [InterviewOption]
    @Binding var selectedOptions: [InterviewOption]
    @Binding var textInput: String
    let allowTwoSelections: Bool
    let isLoading: Bool
    let onSelect: (InterviewOption) -> Void
    let onQuickSelect: (InterviewOption) -> Void
    let onContinue: () -> Void
    @State private var showAllOptions: Bool = false

    private func displayLabel(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleOptions: [InterviewOption] {
        guard options.count > 3, !showAllOptions else { return options }
        var top = Array(options.prefix(3))
        if let noneFit = options.first(where: { $0.id == "none_fit" }), !top.contains(where: { $0.id == noneFit.id }) {
            top.append(noneFit)
        }
        return top
    }

    private var requiresCustomText: Bool {
        selectedOptions.contains(where: { $0.id == "none_fit" })
    }

    private var canContinue: Bool {
        guard !selectedOptions.isEmpty else { return false }
        if requiresCustomText {
            return !textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private var disabledHint: String {
        if selectedOptions.isEmpty {
            return "Select one option to continue."
        }
        if requiresCustomText {
            return "Add your own answer to continue."
        }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(allowTwoSelections ? "Choose up to two for your first version" : "Choose one")
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(visibleOptions) { option in
                    let tapAction = {
                        if !allowTwoSelections && option.id != "none_fit" {
                            onQuickSelect(option)
                        } else {
                            onSelect(option)
                        }
                    }
                    if selectedOptions.contains(where: { $0.id == option.id }) {
                        Button(displayLabel(userFacingOptionLabel(option)), action: tapAction)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .buttonStyle(.borderedProminent)
                            .disabled(isLoading)
                    } else {
                        Button(displayLabel(userFacingOptionLabel(option)), action: tapAction)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .buttonStyle(.bordered)
                            .disabled(isLoading)
                    }
                }
            }
            if options.count > 3 {
                Button(showAllOptions ? "Show fewer choices" : "Show more choices") {
                    showAllOptions.toggle()
                }
                .font(.footnote)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isLoading)
            }
            if selectedOptions.contains(where: { $0.id == "none_fit" }) {
                TextField("Type your own answer", text: $textInput)
                    .textFieldStyle(.roundedBorder)
            }
            if allowTwoSelections || requiresCustomText {
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || !canContinue)

                if !disabledHint.isEmpty {
                    Text(disabledHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Tap one option to continue.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct EvidenceInputView: View {
    @Binding var textInput: String
    let isLoading: Bool
    let onSendEvidence: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            TextField("Describe your app idea...", text: $textInput)
                .textFieldStyle(.roundedBorder)
            Button("Send", action: onSendEvidence)
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .disabled(textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
        }
    }
}

private struct WebsiteContextStepView: View {
    @Binding var ideaInput: String
    @Binding var websiteInput: String
    let isLoading: Bool
    let onStartWithWebsite: () -> Void
    let onStartWithoutWebsite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start your app setup")
                .font(.headline)
            Text("Write your app idea first. If you have a website, add it so ShipFirst can ground your setup.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Describe your app idea in one sentence", text: $ideaInput)
                .textFieldStyle(.roundedBorder)
            Text("Website (optional)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("https://your-site.com", text: $websiteInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Start with Website", action: onStartWithWebsite)
                    .buttonStyle(.borderedProminent)
                    .disabled(ideaInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || websiteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                Button("Skip Website", action: onStartWithoutWebsite)
                    .buttonStyle(.bordered)
                    .disabled(ideaInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
        }
    }
}

private struct CommitReviewCardView: View {
    let blockers: [String]
    let canCommit: Bool
    let improveOption: InterviewOption?
    let onCommitTapped: () -> Void
    let onImproveTapped: (InterviewOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Generate 10-Document Draft")
                .font(.headline)
            if blockers.isEmpty {
                Text("You can generate your first 10-document draft now.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(blockers, id: \.self) { blocker in
                    Text("• \(blocker)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Review before generating", action: onCommitTapped)
                .buttonStyle(.borderedProminent)
                .disabled(!canCommit)
            if let improveOption {
                Button(userFacingOptionLabel(improveOption)) {
                    onImproveTapped(improveOption)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct KodosCommitReviewView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID
    let cycleNo: Int
    let canCommit: Bool
    let blockers: [String]
    let onCommitted: (CommitContractResult) -> Void
    let onCommitBlocked: ([String]) -> Void

    @State private var isLoading: Bool = false
    @State private var localBlockers: [String] = []
    @State private var errorMessage: String?
    @State private var inlineStatusMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Generating now will create your 10-document draft plan.")
                    .foregroundStyle(.secondary)

                if !allBlockers.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What needs one more pass")
                            .font(.headline)
                        ForEach(allBlockers, id: \.self) { blocker in
                            Text("• \(plainEnglishBlocker(blocker))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let inlineStatusMessage {
                    Text(inlineStatusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await commit() }
                } label: {
                    Text("Generate my 10-document draft")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || !allBlockers.isEmpty || !canCommit)

                if !allBlockers.isEmpty {
                    Text("Close this screen, answer one more setup question, then generate again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Review Before Generate")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .overlay {
                if isLoading { ProgressView() }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
                Button("OK") { errorMessage = nil }
            } message: { message in
                Text(message)
            }
        }
    }

    private var allBlockers: [String] {
        var combined = blockers
        combined.append(contentsOf: localBlockers)
        return Array(Set(combined)).sorted()
    }

    private func commit() async {
        guard let api = appState.api else { return }
        inlineStatusMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let outcome = try await api.performTypedAction(projectID: projectID, cycleNo: cycleNo, action: .requestCommit)
            if case .commit(let result) = outcome {
                onCommitted(result)
            }
        } catch AppError.validation(let message, let issues) {
            let merged = issues.isEmpty ? [message] : issues
            let summarized = summarizeCommitIssues(merged)
            localBlockers = summarized
            onCommitBlocked(summarized)
            inlineStatusMessage = plainEnglishBlocker(message)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private func summarizeCommitIssues(_ issues: [String]) -> [String] {
    let normalized = issues.map { $0.lowercased() }
    var summaries: [String] = []

    if normalized.contains(where: { $0.contains("missing required spine sections") }) {
        summaries.append("Some documents are missing core sections (purpose, key decisions, or success checks).")
    }
    if normalized.contains(where: { $0.contains("word budget out of bounds") }) {
        summaries.append("Some documents are too short or too long for a build-ready handoff.")
    }
    if normalized.contains(where: { $0.contains("missing claim provenance refs") || $0.contains("blank claim text") }) {
        summaries.append("Some claims are missing evidence links or complete wording.")
    }
    if normalized.contains(where: { $0.contains("builder notes") }) {
        summaries.append("Builder notes are incomplete in some documents.")
    }

    if summaries.isEmpty {
        summaries.append("The draft still needs a few details before it can be generated.")
    }

    return Array(summaries.prefix(3))
}

struct KodosDocumentsReviewView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID
    let cycleNo: Int
    let initialDocuments: [BrainDocument]?
    let isSubmissionLocked: Bool
    let existingSubmissionPath: String?
    let existingSubmittedAt: String?

    @State private var documents: [BrainDocument] = []
    @State private var reviewConfirmed: Bool = false
    @State private var submissionResult: SubmissionResult?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    private var validation: DocumentValidationResult {
        RunValidator.validate(documents: documents)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Validation") {
                    if validation.isValid {
                        Text("Exactly 10 documents are present and complete.")
                            .foregroundStyle(.green)
                    } else {
                        ForEach(validation.issues, id: \.self) { issue in
                            Text(issue)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Packet") {
                    ForEach(RoleCatalog.orderedRoles) { role in
                        if let document = documents.first(where: { $0.roleID == role.id }) {
                            NavigationLink {
                                KodosDocumentDetailView(document: document)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(role.id). \(role.displayName)")
                                    Text(document.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Submit") {
                    if isSubmissionLocked {
                        Text("Submission recorded")
                            .font(.headline)
                        if let existingSubmissionPath {
                            Text(existingSubmissionPath)
                                .font(.footnote)
                        }
                        if let existingSubmittedAt {
                            Text(existingSubmittedAt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Toggle("I reviewed the packet", isOn: $reviewConfirmed)

                        Button {
                            Task { await submit() }
                        } label: {
                            Text("Confirm Review and Submit")
                        }
                        .disabled(!reviewConfirmed || !validation.isValid || isLoading)

                        if let submissionResult {
                            Text(submissionResult.path)
                                .font(.footnote)
                            Text(submissionResult.submittedAt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Review 10 Docs")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .overlay {
                if isLoading { ProgressView() }
            }
            .task { await loadDocuments() }
            .alert("Error", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
                Button("OK") { errorMessage = nil }
            } message: { message in
                Text(message)
            }
        }
    }

    private func loadDocuments() async {
        if let initialDocuments {
            documents = initialDocuments
            return
        }
        guard let api = appState.api else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            documents = try await api.listLatestDocuments(projectID: projectID, cycleNo: cycleNo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit() async {
        guard let api = appState.api else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let outcome = try await api.performTypedAction(projectID: projectID, cycleNo: cycleNo, action: .confirmReviewAndSubmit)
            if case .submit(let result) = outcome {
                submissionResult = result
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct KodosDocumentDetailView: View {
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
