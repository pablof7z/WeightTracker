import SwiftUI

/// History view: three sections — plan history (newest first), logged misses
/// (newest first), untracked ranges with an "+ Mark range as untracked" CTA.
/// Footer carries the verbatim 3-state legend strings from `MacroCopy`.
struct MacroHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var services: AppServices

    let cutStartDate: Date

    @State private var periods: [MacroPlanPeriod] = []
    @State private var deviations: [MacroDeviation] = []
    @State private var ranges: [MacroUntrackedRange] = []
    @State private var showMarkUntracked = false

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                planSection
                missesSection
                untrackedSection
                legendSection
            }
            .navigationTitle(MacroCopy.historyTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { reload() }
            .sheet(isPresented: $showMarkUntracked) {
                MarkUntrackedSheet(cutStartDate: cutStartDate) {
                    reload()
                }
                .environmentObject(services)
            }
        }
    }

    @ViewBuilder
    private var planSection: some View {
        Section(MacroCopy.historySectionPlan) {
            if periods.isEmpty {
                Text("No plan history yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(periods.reversed(), id: \.id) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(p.kcal.formatted()) kcal")
                                .font(.body.weight(.semibold))
                            if let pr = p.proteinG, let f = p.fatG, let c = p.carbsG {
                                Text("· \(pr)/\(f)/\(c)")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(p.tag.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                        }
                        Text(rangeText(start: p.startDate, end: p.endDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var missesSection: some View {
        Section(MacroCopy.historySectionMisses) {
            if deviations.isEmpty {
                Text("No logged misses.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(deviations, id: \.id) { d in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(Self.dateFmt.string(from: d.date))
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(missLabel(d))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let note = d.note, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            try? services.macroDeviationStore.delete(d)
                            services.cutCoach.refresh(trigger: .macroDeviationChanged)
                            reload()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var untrackedSection: some View {
        Section(MacroCopy.historySectionUntracked) {
            Button {
                showMarkUntracked = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text(MacroCopy.historyMarkUntracked)
                }
            }

            ForEach(ranges, id: \.id) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Self.dateFmt.string(from: r.startDate)) – \(Self.dateFmt.string(from: r.endDate))")
                        .font(.subheadline.weight(.medium))
                    Text(reasonLabel(r))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        services.macroUntrackedRangeStore.delete(r)
                        services.cutCoach.refresh(trigger: .macroUntrackedChanged)
                        reload()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var legendSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(MacroCopy.legendImplicit)
                Text(MacroCopy.legendMiss)
                Text(MacroCopy.legendUntracked)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func reload() {
        periods = services.macroPlanStore.periods(forCutStartDate: cutStartDate)
        deviations = services.macroDeviationStore.deviations(forCutStartDate: cutStartDate)
        ranges = services.macroUntrackedRangeStore.ranges(forCutStartDate: cutStartDate)
    }

    private func rangeText(start: Date, end: Date?) -> String {
        if let end {
            return "\(Self.dateFmt.string(from: start)) – \(Self.dateFmt.string(from: end))"
        } else {
            return "\(Self.dateFmt.string(from: start)) – present"
        }
    }

    private func missLabel(_ d: MacroDeviation) -> String {
        switch (d.direction, d.magnitude) {
        case (.unknown, .wayOff): return "way off"
        case (.over, let m):      return "over · \(m.rawValue)"
        case (.under, let m):     return "under · \(m.rawValue)"
        default:                  return d.magnitude.rawValue
        }
    }

    private func reasonLabel(_ r: MacroUntrackedRange) -> String {
        if r.reason == .custom, let label = r.customReasonLabel, !label.isEmpty {
            return label
        }
        switch r.reason {
        case .travel:  return MacroCopy.untrackedReasonTravel
        case .illness: return MacroCopy.untrackedReasonIllness
        case .life:    return MacroCopy.untrackedReasonLife
        case .custom:  return MacroCopy.untrackedReasonCustom
        }
    }
}
