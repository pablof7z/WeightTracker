import Foundation

struct OpenRouterModelCatalogService: Sendable {
    func fetchModels() async throws -> [OpenRouterModelOption] {
        async let openRouter = fetchOpenRouterModels()
        async let modelsDev = fetchModelsDevCatalogOptional()

        let models = try await openRouter
        let metadata = await modelsDev

        return models
            .map { OpenRouterModelOption(openRouter: $0, modelsDev: metadata) }
            .sorted { lhs, rhs in
                if lhs.isCompatible != rhs.isCompatible { return lhs.isCompatible && !rhs.isCompatible }
                if lhs.createdAt != rhs.createdAt {
                    return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func fetchOpenRouterModels() async throws -> [OpenRouterModel] {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
        request.setValue("WeightTracker", forHTTPHeaderField: "X-Title")

        let data = try await send(request)
        do {
            return try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data).data
        } catch {
            throw OpenRouterModelCatalogError.decoding("OpenRouter models: \(error.localizedDescription)")
        }
    }

    private func fetchModelsDevCatalogOptional() async -> ModelsDevCatalog? {
        do {
            var request = URLRequest(url: URL(string: "https://models.dev/api.json")!)
            request.cachePolicy = .reloadRevalidatingCacheData
            let data = try await send(request)
            let providers = try JSONDecoder().decode([String: ModelsDevProvider].self, from: data)
            return ModelsDevCatalog(providers: providers)
        } catch {
            return nil
        }
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterModelCatalogError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenRouterModelCatalogError.httpStatus(http.statusCode)
        }
        return data
    }
}

struct OpenRouterModelOption: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var providerID: String
    var providerName: String
    var modelDescription: String?
    var promptCostPerMillion: Double?
    var completionCostPerMillion: Double?
    var cacheReadCostPerMillion: Double?
    var cacheWriteCostPerMillion: Double?
    var requestCost: Double?
    var imageCost: Double?
    var webSearchCost: Double?
    var contextLength: Int?
    var outputLimit: Int?
    var inputModalities: [String]
    var outputModalities: [String]
    var tokenizer: String?
    var supportsTools: Bool
    var supportsReasoning: Bool
    var supportsResponseFormat: Bool
    var supportsStructuredOutputs: Bool
    var openWeights: Bool
    var isModerated: Bool?
    var createdAt: Date?
    var knowledgeCutoff: String?
    var releaseDate: String?
    var lastUpdated: String?

    fileprivate init(openRouter model: OpenRouterModel, modelsDev: ModelsDevCatalog?) {
        let devModel = modelsDev?.openRouterModel(id: model.id)
        let providerID = Self.providerID(from: model.id)
        let provider = modelsDev?.provider(id: providerID)
        let supported = Set(model.supportedParameters ?? [])
        let input = model.architecture?.inputModalities ?? devModel?.modalities?.input ?? []
        let output = model.architecture?.outputModalities ?? devModel?.modalities?.output ?? []

        self.id = model.id
        self.name = model.name
        self.providerID = providerID
        self.providerName = Self.providerName(from: model.name, provider: provider, providerID: providerID)
        self.modelDescription = model.description
        self.promptCostPerMillion = model.pricing?.prompt?.costPerMillion ?? devModel?.cost?.input
        self.completionCostPerMillion = model.pricing?.completion?.costPerMillion ?? devModel?.cost?.output
        self.cacheReadCostPerMillion = model.pricing?.inputCacheRead?.costPerMillion ?? devModel?.cost?.cacheRead
        self.cacheWriteCostPerMillion = model.pricing?.inputCacheWrite?.costPerMillion ?? devModel?.cost?.cacheWrite
        self.requestCost = model.pricing?.request.flatMap(Double.init)
        self.imageCost = model.pricing?.image.flatMap(Double.init)
        self.webSearchCost = model.pricing?.webSearch.flatMap(Double.init)
        self.contextLength = model.contextLength ?? model.topProvider?.contextLength ?? devModel?.limit?.context
        self.outputLimit = model.topProvider?.maxCompletionTokens ?? devModel?.limit?.output
        self.inputModalities = input
        self.outputModalities = output
        self.tokenizer = model.architecture?.tokenizer
        self.supportsTools = supported.contains("tools") || devModel?.toolCall == true
        self.supportsReasoning = supported.contains { $0.contains("reasoning") } || devModel?.reasoning == true
        self.supportsStructuredOutputs = supported.contains("structured_outputs") || devModel?.structuredOutput == true
        self.supportsResponseFormat = supported.contains("response_format") || supportsStructuredOutputs
        self.openWeights = devModel?.openWeights == true
        self.isModerated = model.topProvider?.isModerated
        self.createdAt = model.created.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        self.knowledgeCutoff = model.knowledgeCutoff ?? devModel?.knowledge
        self.releaseDate = devModel?.releaseDate
        self.lastUpdated = devModel?.lastUpdated
    }

    var isFree: Bool {
        promptCostPerMillion == 0 && completionCostPerMillion == 0
    }

    var isTextOutput: Bool {
        outputModalities.isEmpty || outputModalities.contains("text")
    }

    var isCompatible: Bool {
        isTextOutput && supportsResponseFormat
    }

    var compactPricing: String {
        guard let input = promptCostPerMillion, let output = completionCostPerMillion else {
            return "Variable"
        }
        if input == 0 && output == 0 {
            return "Free"
        }
        return "\(Self.money(input)) in / \(Self.money(output)) out"
    }

    var searchText: String {
        [
            id,
            name,
            providerName,
            providerID,
            modelDescription ?? "",
            tokenizer ?? "",
            inputModalities.joined(separator: " "),
            outputModalities.joined(separator: " ")
        ].joined(separator: " ").lowercased()
    }

    private static func providerID(from modelID: String) -> String {
        modelID.split(separator: "/", maxSplits: 1).first.map(String.init) ?? "openrouter"
    }

    private static func providerName(from modelName: String, provider: ModelsDevProvider?, providerID: String) -> String {
        if let provider { return provider.name }
        if let colon = modelName.firstIndex(of: ":") {
            return String(modelName[..<colon])
        }
        return providerID
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    static func money(_ value: Double) -> String {
        if value == 0 { return "$0" }
        if value < 0.01 { return String(format: "$%.4f", value) }
        if value < 1 { return String(format: "$%.2f", value) }
        if value.rounded() == value { return String(format: "$%.0f", value) }
        return String(format: "$%.2f", value)
    }

    static func perToken(_ value: Double?) -> String {
        guard let value else { return "Variable" }
        let token = value / 1_000_000
        if token == 0 { return "$0/token" }
        return String(format: "$%.9f/token", token)
    }
}

private enum OpenRouterModelCatalogError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "OpenRouter returned an invalid response."
        case .httpStatus(let status):
            return "OpenRouter model catalog failed with HTTP \(status)."
        case .decoding(let message):
            return message
        }
    }
}

private struct OpenRouterModelsResponse: Decodable, Sendable {
    var data: [OpenRouterModel]
}

private struct OpenRouterModel: Decodable, Sendable {
    var id: String
    var canonicalSlug: String?
    var huggingFaceID: String?
    var name: String
    var created: Int?
    var description: String?
    var contextLength: Int?
    var architecture: OpenRouterArchitecture?
    var pricing: OpenRouterPricing?
    var topProvider: OpenRouterTopProvider?
    var supportedParameters: [String]?
    var knowledgeCutoff: String?
    var expirationDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case canonicalSlug = "canonical_slug"
        case huggingFaceID = "hugging_face_id"
        case name
        case created
        case description
        case contextLength = "context_length"
        case architecture
        case pricing
        case topProvider = "top_provider"
        case supportedParameters = "supported_parameters"
        case knowledgeCutoff = "knowledge_cutoff"
        case expirationDate = "expiration_date"
    }
}

private struct OpenRouterArchitecture: Decodable, Sendable {
    var modality: String?
    var inputModalities: [String]?
    var outputModalities: [String]?
    var tokenizer: String?
    var instructType: String?

    enum CodingKeys: String, CodingKey {
        case modality
        case inputModalities = "input_modalities"
        case outputModalities = "output_modalities"
        case tokenizer
        case instructType = "instruct_type"
    }
}

private struct OpenRouterPricing: Decodable, Sendable {
    var prompt: String?
    var completion: String?
    var request: String?
    var image: String?
    var webSearch: String?
    var internalReasoning: String?
    var inputCacheRead: String?
    var inputCacheWrite: String?

    enum CodingKeys: String, CodingKey {
        case prompt
        case completion
        case request
        case image
        case webSearch = "web_search"
        case internalReasoning = "internal_reasoning"
        case inputCacheRead = "input_cache_read"
        case inputCacheWrite = "input_cache_write"
    }
}

private struct OpenRouterTopProvider: Decodable, Sendable {
    var contextLength: Int?
    var maxCompletionTokens: Int?
    var isModerated: Bool?

    enum CodingKeys: String, CodingKey {
        case contextLength = "context_length"
        case maxCompletionTokens = "max_completion_tokens"
        case isModerated = "is_moderated"
    }
}

private struct ModelsDevCatalog: Sendable {
    var providers: [String: ModelsDevProvider]

    func provider(id: String) -> ModelsDevProvider? {
        providers[id]
    }

    func openRouterModel(id: String) -> ModelsDevModel? {
        providers["openrouter"]?.models[id]
    }
}

private struct ModelsDevProvider: Decodable, Hashable, Sendable {
    var id: String
    var name: String
    var models: [String: ModelsDevModel]
}

private struct ModelsDevModel: Decodable, Hashable, Sendable {
    var id: String
    var name: String
    var family: String?
    var attachment: Bool?
    var reasoning: Bool?
    var toolCall: Bool?
    var structuredOutput: Bool?
    var knowledge: String?
    var releaseDate: String?
    var lastUpdated: String?
    var modalities: ModelsDevModalities?
    var openWeights: Bool?
    var cost: ModelsDevCost?
    var limit: ModelsDevLimit?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case family
        case attachment
        case reasoning
        case toolCall = "tool_call"
        case structuredOutput = "structured_output"
        case knowledge
        case releaseDate = "release_date"
        case lastUpdated = "last_updated"
        case modalities
        case openWeights = "open_weights"
        case cost
        case limit
    }
}

private struct ModelsDevModalities: Decodable, Hashable, Sendable {
    var input: [String]?
    var output: [String]?
}

private struct ModelsDevCost: Decodable, Hashable, Sendable {
    var input: Double?
    var output: Double?
    var cacheRead: Double?
    var cacheWrite: Double?
    var reasoning: Double?

    enum CodingKeys: String, CodingKey {
        case input
        case output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case reasoning
    }
}

private struct ModelsDevLimit: Decodable, Hashable, Sendable {
    var context: Int?
    var output: Int?
}

private extension String {
    var costPerMillion: Double? {
        guard let value = Double(self), value >= 0 else { return nil }
        return value * 1_000_000
    }
}
