import SwiftUI

/// Date-range + reason picker for marking a span as "untracked". Validation:
/// `start ≤ end ≤ today`. The cut-start gates the lower bound — there's no
/// reason to mark days before the cut began.
struct MarkUntrackedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var services: AppServices

    let cutStartDate: Date
    var onSaved: (() -> Void)? = nil

    @State private var start: Date = Date()
    @State private var end: Date = Date()
    @State private var reason: UntrackedReason = .life
    @State private var customLabel: String = ""
    @State private var errorText: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        MacroCopy.untrackedFrom,
                        selection: $start,
                        in: cutStartDate...Date(),
                        displayedComponents: .date
                    )
                    DatePicker(
                        MacroCopy.untrackedTo,
                        selection: $end,
                        in: start...Date(),
                        displayedComponents: .date
                    )
                }

                Section {
                    HStack(spacing: 8) {
                        reasonChip(.travel,  MacroCopy.untrackedReasonTravel)
                        reasonChip(.illness, MacroCopy.untrackedReasonIllness)
                        reasonChip(.life,    MacroCopy.untrackedReasonLife)
                        reasonChip(.custom,  MacroCopy.untrackedReasonCustom)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))

                    if reason == .custom {
                        TextField(MacroCopy.untrackedCustomLabelPlaceholder, text: $customLabel)
                    }
                } header: {
                    Text("Reason")
                } footer: {
                    if let errorText {
                        Text(errorText).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        save()
                    } label: {
                        Text(MacroCopy.untrackedSave)
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                }
            }
            .navigationTitle(MacroCopy.untrackedTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func reasonChip(_ value: UntrackedReason, _ label: String) -> some View {
        let selected = (reason == value)
        Button {
            reason = value
        } label: {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(
                    selected ? Color.accentColor.opacity(0.18) : Color.clear,
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3))
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func save() {
        do {
            _ = try services.macroUntrackedRangeStore.insert(
                cutStartDate: cutStartDate,
                startDate: start,
                endDate: end,
                reason: reason,
                customReasonLabel: reason == .custom ? customLabel.trimmingCharacters(in: .whitespaces) : nil
            )
            onSaved?()
            dismiss()
        } catch let err as MacroUntrackedRangeError {
            errorText = MacroCopy.untrackedError(err)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
