import SwiftUI

struct OpenRouterModelSelectorView: View {
    @Binding var selectedModelID: String
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = OpenRouterModelSelectorViewModel()
    @State private var searchText = ""
    @State private var capabilityFilter: ModelCapabilityFilter = .compatible
    @State private var sort: ModelSort = .recommended
    @State private var providerFilter: String?
    @State private var manualModelID = ""

    var body: some View {
        List {
            currentSection
            controlsSection
            loadingSection
            modelsSection
            customSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("OpenRouter Models")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search models, providers, ids")
        .refreshable { await viewModel.reload() }
        .task {
            if manualModelID.isEmpty { manualModelID = selectedModelID }
            await viewModel.loadIfNeeded()
        }
        .navigationDestination(for: OpenRouterModelOption.self) { model in
            OpenRouterModelDetailView(
                model: model,
                selectedModelID: selectedModelID
            ) {
                selectedModelID = model.id
                dismiss()
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                providerMenu
                Button {
                    Task { await viewModel.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .accessibilityLabel("Refresh models")
            }
        }
    }

    private var currentSection: some View {
        Section("Current") {
            if let current = viewModel.models.first(where: { $0.id == selectedModelID }) {
                NavigationLink(value: current) {
                    OpenRouterModelRow(model: current, isSelected: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedModelID)
                        .font(.subheadline.monospaced())
                    Text("Custom model ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var controlsSection: some View {
        Section {
            Picker("Filter", selection: $capabilityFilter) {
                ForEach(ModelCapabilityFilter.allCases) { filter in
                    Label(filter.title, systemImage: filter.systemImage)
                        .tag(filter)
                }
            }

            Picker("Sort", selection: $sort) {
                ForEach(ModelSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }

            if let providerFilter,
               let providerName = providerName(for: providerFilter) {
                Button {
                    self.providerFilter = nil
                } label: {
                    Label("Provider: \(providerName)", systemImage: "xmark.circle")
                }
            }
        }
    }

    @ViewBuilder
    private var loadingSection: some View {
        if viewModel.isLoading && viewModel.models.isEmpty {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading models")
                        .foregroundStyle(.secondary)
                }
            }
        }

        if let error = viewModel.errorMessage {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)

                    Button {
                        Task { await viewModel.reload() }
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var modelsSection: some View {
        Section("\(visibleModels.count) Models") {
            if visibleModels.isEmpty && !viewModel.isLoading {
                Text("No models match this search")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleModels) { model in
                    NavigationLink(value: model) {
                        OpenRouterModelRow(model: model, isSelected: model.id == selectedModelID)
                    }
                }
            }
        }
    }

    private var customSection: some View {
        Section("Custom model ID") {
            TextField("provider/model", text: $manualModelID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())

            Button {
                let trimmed = manualModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                selectedModelID = trimmed
                dismiss()
            } label: {
                Label("Use custom ID", systemImage: "checkmark.circle")
            }
            .disabled(manualModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var providerMenu: some View {
        Menu {
            Button {
                providerFilter = nil
            } label: {
                Label("All providers", systemImage: providerFilter == nil ? "checkmark" : "building.2")
            }

            ForEach(providerSummaries) { provider in
                Button {
                    providerFilter = provider.id
                } label: {
                    if providerFilter == provider.id {
                        Label("\(provider.name) (\(provider.count))", systemImage: "checkmark")
                    } else {
                        Text("\(provider.name) (\(provider.count))")
                    }
                }
            }
        } label: {
            Image(systemName: "building.2")
        }
        .accessibilityLabel("Filter by provider")
    }

    private var visibleModels: [OpenRouterModelOption] {
        var models = viewModel.models

        if let providerFilter {
            models = models.filter { $0.providerID == providerFilter }
        }

        models = models.filter { capabilityFilter.matches($0) }

        let terms = searchText
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        if !terms.isEmpty {
            models = models.filter { model in
                terms.allSatisfy { model.searchText.contains($0) }
            }
        }

        switch sort {
        case .recommended:
            return models
        case .newest:
            return models.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .price:
            return models.sorted { lhs, rhs in
                lhs.priceSortValue < rhs.priceSortValue
            }
        case .context:
            return models.sorted { ($0.contextLength ?? 0) > ($1.contextLength ?? 0) }
        case .name:
            return models.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var providerSummaries: [ProviderSummary] {
        let grouped = Dictionary(grouping: viewModel.models, by: \.providerID)
        return grouped.map { id, models in
            ProviderSummary(
                id: id,
                name: models.first?.providerName ?? id,
                count: models.count
            )
        }
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        .prefix(24)
        .map { $0 }
    }

    private func providerName(for id: String) -> String? {
        viewModel.models.first { $0.providerID == id }?.providerName
    }
}

@MainActor
private final class OpenRouterModelSelectorViewModel: ObservableObject {
    @Published private(set) var models: [OpenRouterModelOption] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service = OpenRouterModelCatalogService()

    func loadIfNeeded() async {
        guard models.isEmpty else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            models = try await service.fetchModels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct OpenRouterModelRow: View {
    var model: OpenRouterModelOption
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProviderLogoView(providerID: model.providerID, providerName: model.providerName)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .imageScale(.small)
                    }
                }

                Text(model.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    ForEach(badges.prefix(4), id: \.self) { badge in
                        ModelBadge(text: badge)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(model.compactPricing)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.primary)
                Text("per 1M")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(tokenLimit(model.contextLength))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 86, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private var badges: [String] {
        var result: [String] = []
        result.append(model.isCompatible ? "JSON" : "No JSON")
        if model.supportsTools { result.append("Tools") }
        if model.supportsReasoning { result.append("Reasoning") }
        if model.inputModalities.contains("image") { result.append("Vision") }
        if model.openWeights { result.append("Open") }
        if model.isFree { result.append("Free") }
        return result
    }
}

private struct OpenRouterModelDetailView: View {
    var model: OpenRouterModelOption
    var selectedModelID: String
    var onSelect: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    ProviderLogoView(
                        providerID: model.providerID,
                        providerName: model.providerName,
                        size: 52
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.name)
                            .font(.title3.weight(.semibold))
                        Text(model.id)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(model.providerName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(action: onSelect) {
                    Label(selectedModelID == model.id ? "Selected" : "Use Model", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedModelID == model.id)

                detailGroup("Pricing") {
                    DetailLine("Prompt", pricingDetail(model.promptCostPerMillion))
                    DetailLine("Completion", pricingDetail(model.completionCostPerMillion))
                    if model.cacheReadCostPerMillion != nil {
                        DetailLine("Cache read", pricingDetail(model.cacheReadCostPerMillion))
                    }
                    if model.cacheWriteCostPerMillion != nil {
                        DetailLine("Cache write", pricingDetail(model.cacheWriteCostPerMillion))
                    }
                    if let webSearchCost = model.webSearchCost {
                        DetailLine("Web search", OpenRouterModelOption.money(webSearchCost))
                    }
                    if let imageCost = model.imageCost {
                        DetailLine("Image", OpenRouterModelOption.money(imageCost))
                    }
                }

                detailGroup("Capabilities") {
                    DetailLine("Compatibility", model.isCompatible ? "JSON response format" : "May not support JSON schema")
                    DetailLine("Input", model.inputModalities.isEmpty ? "Unknown" : model.inputModalities.joined(separator: ", "))
                    DetailLine("Output", model.outputModalities.isEmpty ? "Unknown" : model.outputModalities.joined(separator: ", "))
                    DetailLine("Tools", model.supportsTools ? "Yes" : "No")
                    DetailLine("Reasoning", model.supportsReasoning ? "Yes" : "No")
                    DetailLine("Structured output", model.supportsStructuredOutputs ? "Yes" : "No")
                    DetailLine("Weights", model.openWeights ? "Open" : "Closed")
                }

                detailGroup("Limits") {
                    DetailLine("Context", tokenLimit(model.contextLength))
                    DetailLine("Output", tokenLimit(model.outputLimit))
                    if let tokenizer = model.tokenizer {
                        DetailLine("Tokenizer", tokenizer)
                    }
                    if let isModerated = model.isModerated {
                        DetailLine("Moderated", isModerated ? "Yes" : "No")
                    }
                }

                detailGroup("Dates") {
                    if let releaseDate = model.releaseDate {
                        DetailLine("Release", releaseDate)
                    }
                    if let lastUpdated = model.lastUpdated {
                        DetailLine("Updated", lastUpdated)
                    }
                    if let knowledgeCutoff = model.knowledgeCutoff {
                        DetailLine("Knowledge", knowledgeCutoff)
                    }
                    if let createdAt = model.createdAt {
                        DetailLine("OpenRouter added", createdAt.formatted(date: .abbreviated, time: .omitted))
                    }
                }

                if let description = model.modelDescription, !description.isEmpty {
                    detailGroup("Description") {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Model")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pricingDetail(_ value: Double?) -> String {
        guard let value else { return "Variable" }
        return "\(OpenRouterModelOption.perToken(value)) / \(OpenRouterModelOption.money(value)) per 1M"
    }
}

private struct DetailLine: View {
    var label: String
    var value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }
}

private struct ModelBadge: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(text == "No JSON" ? .orange : .secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
    }
}

private enum ModelCapabilityFilter: String, CaseIterable, Identifiable {
    case compatible
    case all
    case free
    case tools
    case reasoning
    case vision
    case openWeights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compatible: return "Compatible"
        case .all: return "All"
        case .free: return "Free"
        case .tools: return "Tools"
        case .reasoning: return "Reasoning"
        case .vision: return "Vision"
        case .openWeights: return "Open weights"
        }
    }

    var systemImage: String {
        switch self {
        case .compatible: return "curlybraces"
        case .all: return "line.3.horizontal.decrease.circle"
        case .free: return "dollarsign.circle"
        case .tools: return "wrench.and.screwdriver"
        case .reasoning: return "brain"
        case .vision: return "eye"
        case .openWeights: return "lock.open"
        }
    }

    func matches(_ model: OpenRouterModelOption) -> Bool {
        switch self {
        case .compatible: return model.isCompatible
        case .all: return true
        case .free: return model.isFree
        case .tools: return model.supportsTools
        case .reasoning: return model.supportsReasoning
        case .vision: return model.inputModalities.contains("image")
        case .openWeights: return model.openWeights
        }
    }
}

private enum ModelSort: String, CaseIterable, Identifiable {
    case recommended
    case newest
    case price
    case context
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended: return "Recommended"
        case .newest: return "Newest"
        case .price: return "Lowest price"
        case .context: return "Largest context"
        case .name: return "Name"
        }
    }
}

private struct ProviderSummary: Identifiable, Hashable {
    var id: String
    var name: String
    var count: Int
}

private extension OpenRouterModelOption {
    var priceSortValue: Double {
        guard let promptCostPerMillion, let completionCostPerMillion else {
            return .greatestFiniteMagnitude
        }
        return promptCostPerMillion + completionCostPerMillion
    }
}

private func tokenLimit(_ value: Int?) -> String {
    guard let value else { return "Unknown" }
    if value >= 1_000_000 {
        let millions = Double(value) / 1_000_000
        return String(format: "%.1fM tokens", millions)
    }
    if value >= 1_000 {
        return "\(value / 1_000)K tokens"
    }
    return "\(value) tokens"
}
