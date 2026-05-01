import SwiftUI

struct CutCoachCard: View {
    let plan: CutCoachPlan
    var onSelectMissingDetail: ((CutCoachMissingDetailChip) -> Void)? = nil
    var onShowAudit: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            targetGrid

            if !plan.reasons.isEmpty {
                Divider()
                reasonsSection
            }

            if let prompt = plan.missingDetailPrompt {
                Divider()
                missingDetailSection(prompt)
            }
        }
        .padding(14)
        .glass(in: RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Cut Coach", systemImage: "scissors")
                .font(.headline)
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 2) {
                Text(plan.weekStatus)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if let decision = plan.weekDecision {
                    Text(decision)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            if let onShowAudit {
                Button(action: onShowAudit) {
                    Image(systemName: "list.bullet.clipboard")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open coach audit")
            }
        }
    }

    private var targetGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                targetTile(
                    icon: "flame",
                    title: CutCoachCopy.calories,
                    value: "\(plan.calories)",
                    unit: "kcal"
                )
                macroTile
            }

            GridRow {
                targetTile(
                    icon: "figure.walk",
                    title: CutCoachCopy.steps,
                    value: plan.steps.map(Self.formatWholeNumber) ?? "—",
                    unit: plan.steps == nil ? nil : "steps"
                )
                targetTile(
                    icon: "dumbbell",
                    title: CutCoachCopy.training,
                    value: plan.trainingTarget ?? "—",
                    unit: nil
                )
            }
        }
    }

    private var macroTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Macros", systemImage: "chart.pie")
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            HStack(spacing: 8) {
                macroCell("P", grams: plan.proteinG)
                macroCell("F", grams: plan.fatG)
                macroCell("C", grams: plan.carbsG)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func targetTile(icon: String, title: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if let unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func macroCell(_ label: String, grams: Int?) -> some View {
        let fullName: String = {
            switch label {
            case "P": return "Protein"
            case "F": return "Fat"
            case "C": return "Carbs"
            default: return label
            }
        }()
        return HStack(spacing: 3) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(grams.map { "\($0)" } ?? "—")
                .font(.subheadline.monospacedDigit().weight(.semibold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(grams.map { "\(fullName) \($0) grams" } ?? "\(fullName) not set")
    }

    private var reasonsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CutCoachCopy.reasons)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(plan.reasons.prefix(5), id: \.self) { reason in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(Color.secondary.opacity(0.55))
                        .frame(width: 4, height: 4)
                        .accessibilityHidden(true)
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func missingDetailSection(_ prompt: CutCoachMissingDetailPrompt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CutCoachCopy.needOneDetail)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(prompt.question)
                .font(.subheadline)
                .lineLimit(2)

            if onSelectMissingDetail != nil {
                FlowLayout(spacing: 8, rowSpacing: 8) {
                    ForEach(prompt.chips) { chip in
                        Button {
                            onSelectMissingDetail?(chip)
                        } label: {
                            Text(chip.label)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .glass(in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private static func formatWholeNumber(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}

struct CutCoachPlan: Equatable {
    var calories: Int
    var proteinG: Int?
    var fatG: Int?
    var carbsG: Int?
    var steps: Int?
    var trainingTarget: String?
    var weekStatus: String
    var weekDecision: String?
    var reasons: [String]
    var missingDetailPrompt: CutCoachMissingDetailPrompt?

    init(
        calories: Int,
        proteinG: Int? = nil,
        fatG: Int? = nil,
        carbsG: Int? = nil,
        steps: Int? = nil,
        trainingTarget: String? = nil,
        weekStatus: String,
        weekDecision: String? = nil,
        reasons: [String] = [],
        missingDetailPrompt: CutCoachMissingDetailPrompt? = nil
    ) {
        self.calories = calories
        self.proteinG = proteinG
        self.fatG = fatG
        self.carbsG = carbsG
        self.steps = steps
        self.trainingTarget = trainingTarget
        self.weekStatus = weekStatus
        self.weekDecision = weekDecision
        self.reasons = reasons
        self.missingDetailPrompt = missingDetailPrompt
    }
}

struct CutCoachMissingDetailPrompt: Equatable {
    var question: String
    var chips: [CutCoachMissingDetailChip]

    init(
        question: String,
        chips: [CutCoachMissingDetailChip] = CutCoachMissingDetailChip.allCases
    ) {
        self.question = question
        self.chips = chips
    }
}

enum CutCoachMissingDetailChip: String, CaseIterable, Identifiable {
    case restaurant
    case travel
    case hardTraining
    case poorSleep
    case missedLog
    case nothing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .restaurant: return "Restaurant"
        case .travel: return "Travel"
        case .hardTraining: return "Hard training"
        case .poorSleep: return "Poor sleep"
        case .missedLog: return "Missed log"
        case .nothing: return "Nothing"
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        layout(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let result = layout(in: bounds.width, subviews: subviews)
        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + result.origins[index].x,
                    y: bounds.minY + result.origins[index].y
                ),
                proposal: .unspecified
            )
        }
    }

    private func layout(in maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var cursor = CGPoint.zero
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let startsNewRow = cursor.x > 0 && cursor.x + size.width > maxWidth

            if startsNewRow {
                cursor.x = 0
                cursor.y += rowHeight + rowSpacing
                rowHeight = 0
            }

            origins.append(cursor)
            width = max(width, cursor.x + size.width)
            rowHeight = max(rowHeight, size.height)
            cursor.x += size.width + spacing
        }

        return (
            CGSize(width: width, height: cursor.y + rowHeight),
            origins
        )
    }
}

#Preview("Complete") {
    CutCoachCard(
        plan: CutCoachPlan(
            calories: 1_950,
            proteinG: 170,
            fatG: 58,
            carbsG: 185,
            steps: 10_500,
            trainingTarget: "Lower",
            weekStatus: "Slightly behind",
            weekDecision: "Hold calories",
            reasons: [
                "7-day average is 0.3 lb above the target line.",
                "Two missed logs this week reduce confidence.",
                "Steps are 1,200 under target on average.",
                "Training day needs more carbs than rest day."
            ],
            missingDetailPrompt: CutCoachMissingDetailPrompt(
                question: "What explains yesterday's gap?"
            )
        )
    )
    .padding()
}

#Preview("No question") {
    CutCoachCard(
        plan: CutCoachPlan(
            calories: 2_080,
            proteinG: 165,
            fatG: 62,
            carbsG: 210,
            steps: 9_000,
            weekStatus: "On plan",
            weekDecision: "No change",
            reasons: [
                "Weekly loss rate matches the current target.",
                "Macro misses are within the normal range.",
                "Step average is close to target."
            ]
        )
    )
    .padding()
}
