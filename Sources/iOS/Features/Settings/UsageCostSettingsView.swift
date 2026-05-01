import Charts
import SwiftUI

struct UsageCostSettingsView: View {
    @StateObject private var ledger = CostLedger.shared
    @State private var range: CostRange = .last7Days
    @State private var confirmClear = false

    var body: some View {
        Group {
            if ledger.records.isEmpty {
                empty
            } else {
                scroll
            }
        }
        .navigationTitle("Usage & Cost")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !ledger.records.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            confirmClear = true
                        } label: {
                            Label("Clear log", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog(
            "Clear usage log?",
            isPresented: $confirmClear,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) { ledger.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes all usage history.")
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("No usage yet", systemImage: "dollarsign.circle")
        } description: {
            Text("Cost and token counts will appear here after the next AI call.")
        }
    }

    private var scroll: some View {
        let filtered = filteredRecords
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                rangePicker
                heroStats(for: filtered)
                dailyChart(for: filtered)
                breakdownSection(
                    title: "By feature",
                    buckets: aggregate(filtered, by: { CostFeature.displayName(for: $0.feature) })
                )
                breakdownSection(
                    title: "By model",
                    buckets: aggregate(filtered, by: \.model)
                )
                recentCalls(for: filtered)
                allTimeFooter
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .background(Color(.systemBackground))
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(CostRange.allCases) { r in
                Text(r.shortLabel).tag(r)
            }
        }
        .pickerStyle(.segmented)
    }

    private func heroStats(for records: [UsageRecord]) -> some View {
        let totalCost = records.reduce(0) { $0 + $1.costUSD }
        let totalCalls = records.count
        let avg = totalCalls == 0 ? 0 : totalCost / Double(totalCalls)
        let avgLatency = totalCalls == 0 ? 0 : records.reduce(0) { $0 + $1.latencyMs } / totalCalls

        return VStack(alignment: .leading, spacing: 12) {
            Text(range.displayLabel)
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            Text(formatUSD(totalCost))
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)

            HStack(spacing: 18) {
                metric(value: "\(totalCalls)", label: "calls")
                Divider().frame(height: 28)
                metric(value: formatUSDCompact(avg), label: "avg / call")
                Divider().frame(height: 28)
                metric(value: formatLatency(avgLatency), label: "avg latency")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func dailyChart(for records: [UsageRecord]) -> some View {
        let series = dailySeries(for: records)
        if series.isEmpty {
            emptyCard(text: "No spend in this range.")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Daily spend")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                Chart(series) { point in
                    BarMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Cost", point.cost)
                    )
                    .foregroundStyle(by: .value("Feature", CostFeature.displayName(for: point.feature)))
                    .cornerRadius(2)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: xAxisStride)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: xAxisFormat)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = value.as(Double.self) {
                                Text(formatUSDAxis(d))
                            }
                        }
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
                .frame(height: 180)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    private func breakdownSection(title: String, buckets: [Bucket]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            if buckets.isEmpty {
                Text("No data in this range.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    let maxCost = max(buckets.map(\.cost).max() ?? 0, 0.0001)
                    ForEach(buckets) { bucket in
                        bucketRow(bucket, maxCost: maxCost)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func bucketRow(_ bucket: Bucket, maxCost: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(bucket.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(formatUSD(bucket.cost))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.primary)
            }

            GeometryReader { geo in
                let fraction = max(0.02, CGFloat(bucket.cost / maxCost))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * fraction, height: 6)
                }
            }
            .frame(height: 6)

            HStack(spacing: 8) {
                Text("\(bucket.count) calls")
                Text("·")
                Text("avg \(formatUSDCompact(bucket.cost / Double(max(bucket.count, 1))))")
                if bucket.cachedTokens > 0 {
                    Text("·")
                    Text("\(bucket.cachedTokens.formatted()) cached")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func recentCalls(for records: [UsageRecord]) -> some View {
        let recent = Array(records.prefix(50))
        return VStack(alignment: .leading, spacing: 12) {
            Text("Recent calls")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            if recent.isEmpty {
                Text("No calls in this range.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, record in
                        recentRow(record)
                        if index != recent.count - 1 {
                            Divider()
                        }
                    }
                }
            }

            if records.count > recent.count {
                Text("Showing 50 of \(records.count) in this range.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func recentRow(_ record: UsageRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(CostFeature.displayName(for: record.feature))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Text(record.model)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Text(record.at.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text("\(record.promptTokens.formatted())→\(record.completionTokens.formatted()) tok")
                    if record.cachedTokens > 0 {
                        Text("·")
                        Text("\(record.cachedTokens.formatted()) cached")
                    }
                    if record.reasoningTokens > 0 {
                        Text("·")
                        Text("\(record.reasoningTokens.formatted()) reasoning")
                    }
                    Text("·")
                    Text(formatLatency(record.latencyMs))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            Text(formatUSD(record.costUSD))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 10)
    }

    private var allTimeFooter: some View {
        let all = ledger.records
        let total = all.reduce(0) { $0 + $1.costUSD }
        let first = all.last?.at
        return HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
            Text("Lifetime \(formatUSD(total)) across \(all.count) calls")
                .foregroundStyle(.secondary)
            if let first {
                Text("·")
                Text("since \(first.formatted(date: .abbreviated, time: .omitted))")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.caption)
        .padding(.vertical, 4)
    }

    private func emptyCard(text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
    }

    // MARK: Data shaping

    private var filteredRecords: [UsageRecord] {
        guard let since = range.since(now: Date()) else { return ledger.records }
        return ledger.records.filter { $0.at >= since }
    }

    private struct Bucket: Identifiable {
        let id: String
        let name: String
        let cost: Double
        let count: Int
        let cachedTokens: Int
    }

    private func aggregate(_ records: [UsageRecord], by key: (UsageRecord) -> String) -> [Bucket] {
        var grouped: [String: (cost: Double, count: Int, cached: Int)] = [:]
        for r in records {
            let k = key(r)
            var entry = grouped[k] ?? (0, 0, 0)
            entry.cost += r.costUSD
            entry.count += 1
            entry.cached += r.cachedTokens
            grouped[k] = entry
        }
        return grouped
            .map { Bucket(id: $0.key, name: $0.key, cost: $0.value.cost, count: $0.value.count, cachedTokens: $0.value.cached) }
            .sorted { $0.cost > $1.cost }
    }

    private struct DailyPoint: Identifiable {
        let id: String
        let day: Date
        let feature: String
        let cost: Double
    }

    private func dailySeries(for records: [UsageRecord]) -> [DailyPoint] {
        let cal = Calendar.current
        var grouped: [String: (day: Date, feature: String, cost: Double)] = [:]
        for r in records {
            let day = cal.startOfDay(for: r.at)
            let key = "\(day.timeIntervalSince1970)|\(r.feature)"
            var entry = grouped[key] ?? (day, r.feature, 0)
            entry.cost += r.costUSD
            grouped[key] = entry
        }
        return grouped
            .map { DailyPoint(id: $0.key, day: $0.value.day, feature: $0.value.feature, cost: $0.value.cost) }
            .sorted { $0.day < $1.day }
    }

    private var xAxisStride: Calendar.Component {
        switch range {
        case .today: return .hour
        case .last7Days: return .day
        case .last30Days: return .day
        case .all: return .weekOfYear
        }
    }

    private var xAxisFormat: Date.FormatStyle {
        switch range {
        case .today: return .dateTime.hour()
        case .last7Days, .last30Days: return .dateTime.month(.abbreviated).day()
        case .all: return .dateTime.month(.abbreviated).day()
        }
    }

    // MARK: Formatting

    private func formatUSD(_ value: Double) -> String {
        if value == 0 { return "$0.00" }
        if value < 0.01 { return String(format: "$%.4f", value) }
        if value < 1 { return String(format: "$%.3f", value) }
        return String(format: "$%.2f", value)
    }

    private func formatUSDCompact(_ value: Double) -> String {
        if value == 0 { return "$0" }
        if value < 0.001 { return String(format: "$%.4f", value) }
        if value < 1 { return String(format: "$%.3f", value) }
        return String(format: "$%.2f", value)
    }

    private func formatUSDAxis(_ value: Double) -> String {
        if value == 0 { return "$0" }
        if value < 0.01 { return String(format: "$%.3f", value) }
        if value < 1 { return String(format: "$%.2f", value) }
        return String(format: "$%.0f", value)
    }

    private func formatLatency(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        return String(format: "%.1fs", Double(ms) / 1000)
    }
}

enum CostRange: String, CaseIterable, Identifiable {
    case today
    case last7Days
    case last30Days
    case all

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .today: return "Today"
        case .last7Days: return "7 days"
        case .last30Days: return "30 days"
        case .all: return "All"
        }
    }

    var displayLabel: String {
        switch self {
        case .today: return "Today"
        case .last7Days: return "Last 7 days"
        case .last30Days: return "Last 30 days"
        case .all: return "All time"
        }
    }

    func since(now: Date) -> Date? {
        let cal = Calendar.current
        switch self {
        case .today: return cal.startOfDay(for: now)
        case .last7Days: return cal.date(byAdding: .day, value: -7, to: now)
        case .last30Days: return cal.date(byAdding: .day, value: -30, to: now)
        case .all: return nil
        }
    }
}
