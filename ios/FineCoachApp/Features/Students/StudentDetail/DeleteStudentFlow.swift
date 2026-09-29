import SwiftUI

enum DeleteStudentFinish: Equatable, Sendable {
    case cancelled
    case deleted
    case backup
    case continueTraining
}

struct ArchiveStudentView: View {
    let studentID: StableUUID
    let useCases: StudentUseCases
    let onCancel: () -> Void
    let onArchived: () -> Void
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space4) {
            Text(String(localized: "student.archive.lead"))
                .fcFont(.title)
            VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                Text("• " + String(localized: "student.archive.effect.hidden"))
                Text("• " + String(localized: "student.archive.effect.noSession"))
                Text("• " + String(localized: "student.archive.effect.history"))
                Text("• " + String(localized: "student.archive.effect.restore"))
            }
            Text(String(localized: "student.archive.hint"))
                .foregroundStyle(FCSemanticColors.textSecondary)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(FCSemanticColors.statusDestructive)
            }
            FCButton(title: String(localized: "student.detail.archive")) {
                Task {
                    do {
                        _ = try await useCases.archive(id: studentID)
                        onArchived()
                    } catch {
                        errorMessage =
                            (error as? LocalizedError)?.errorDescription
                            ?? String(localized: "student.error.generic")
                    }
                }
            }
            .accessibilityIdentifier(FCAccessibilityID.archiveConfirm)
            Spacer()
        }
        .padding(FCPrimitives.space4)
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(String(localized: "student.archive.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "student.flow.cancel"), action: onCancel)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
    }
}

struct DeleteStudentFlow: View {
    let studentID: StableUUID
    let useCases: StudentUseCases
    let onFinish: (DeleteStudentFinish) -> Void
    @State private var impact: StudentDeletionImpact?
    @State private var typedName = ""
    @State private var errorMessage: String?
    @State private var didDelete = false

    var body: some View {
        Group {
            if didDelete {
                deletedState
            } else if let impact, impact.hasInProgressSession {
                blockedState(impact)
            } else if let impact {
                confirmState(impact)
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(FCSemanticColors.statusDestructive)
            } else {
                ProgressView()
            }
        }
        .task { await load() }
        .padding(FCPrimitives.space4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(String(localized: "student.delete.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "student.flow.cancel")) {
                    onFinish(.cancelled)
                }
                .frame(minWidth: 44, minHeight: 44)
            }
        }
    }

    private var deletedState: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space4) {
            Text(String(localized: "student.delete.done"))
                .fcFont(.title)
            FCButton(title: String(localized: "student.delete.backToList")) {
                onFinish(.deleted)
            }
        }
    }

    private func blockedState(_ impact: StudentDeletionImpact) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space4) {
            Text(String(format: String(localized: "student.delete.blocked"), impact.displayName))
                .fcFont(.title)
                .accessibilityIdentifier(FCAccessibilityID.deleteBlocked)
            Text(String(localized: "student.delete.blockedHint"))
                .foregroundStyle(FCSemanticColors.textSecondary)
            FCButton(title: String(localized: "student.list.continue")) {
                onFinish(.continueTraining)
            }
            Button {
                onFinish(.cancelled)
            } label: {
                Text(String(localized: "student.delete.backToDetail"))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
    }

    private func confirmState(_ impact: StudentDeletionImpact) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space4) {
            Text(String(format: String(localized: "student.delete.lead"), impact.displayName))
            Text(String(localized: "student.delete.affect"))
                .fcFont(.headline)
            Text("• " + String(localized: "student.delete.affect.profile"))
            Text("• " + String(localized: "student.delete.affect.notes"))
            Text(
                "• "
                    + String(
                        format: String(localized: "student.delete.affect.historyCount"),
                        locale: .current,
                        Int64(impact.completedSessionCount)
                    )
            )
            FCButton(title: String(localized: "student.delete.backup")) {
                onFinish(.backup)
            }
            .accessibilityIdentifier(FCAccessibilityID.deleteBackup)
            Text(String(localized: "student.delete.namePrompt"))
            FCTextField(String(localized: "student.field.displayName"), text: $typedName)
                .accessibilityIdentifier(FCAccessibilityID.deleteName)
                .accessibilityLabel(String(localized: "student.delete.namePrompt"))
            if let errorMessage {
                Text(errorMessage).foregroundStyle(FCSemanticColors.statusDestructive)
            }
            Text(String(localized: "student.delete.boundary"))
                .fcFont(.caption)
                .foregroundStyle(FCSemanticColors.textSecondary)
            FCButton(
                title: String(localized: "student.delete.confirm"),
                isEnabled: namesMatch(impact.displayName)
            ) {
                Task { await confirmDelete() }
            }
            .accessibilityIdentifier(FCAccessibilityID.deleteConfirm)
        }
    }

    private func namesMatch(_ expected: String) -> Bool {
        typedName.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping == expected
    }

    private func load() async {
        do {
            impact = try await useCases.deletionImpact(id: studentID)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }

    private func confirmDelete() async {
        do {
            try await useCases.delete(id: studentID, confirmedDisplayName: typedName)
            didDelete = true
        } catch DomainError.invalidState {
            errorMessage = String(localized: "student.delete.mismatch")
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "student.error.generic")
        }
    }
}
