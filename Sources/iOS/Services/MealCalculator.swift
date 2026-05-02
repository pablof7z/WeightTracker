import Foundation

// MARK: - Public DTOs

/// Result of nutrition lookup for a single food item, after parsing,
/// USDA lookup, and (optional) cooked → raw correction.
struct CalculatedFoodItem: Codable, Sendable, Equatable {
    let input: String
    let food: String
    let fdcId: Int?
    let dataType: String?
    let grams: Double               // user's stated grams (post-LLM normalization)
    let rawEquivalentGrams: Double  // grams after cooking correction
    let state: String               // "raw" | "cooked" | "unspecified"
    let stateAdjustment: CookingAdjustmentInfo?
    let kcal: Int
    let proteinG: Double
    let fatG: Double
    let carbsG: Double
    let confidence: String          // "high" | "medium" | "low" | "unavailable"
    let source: String              // "usda-fdc" | "llm-estimate" | "cache"
    let warnings: [String]
}

struct CookingAdjustmentInfo: Codable, Sendable, Equatable {
    let fromState: String   // "cooked"
    let toState: String     // "raw-equivalent"
    let factor: Double      // e.g. 0.75
    let rule: String        // e.g. "chickenBreast-cooked-to-raw"
}

struct MacroTotals: Codable, Sendable, Equatable {
    let kcal: Int
    let proteinG: Double
    let fatG: Double
    let carbsG: Double
}

struct CalculateMealResult: Codable, Sendable, Equatable {
    let items: [CalculatedFoodItem]
    let total: MacroTotals
    let warnings: [String]
    let schemaVersion: String   // "calculate-meal-v1"
}

// MARK: - Inner-LLM parsing

/// Single food item as produced by the inner LLM call (gpt-4o-mini).
/// We deliberately ask the model NOT to estimate macros — that responsibility
/// belongs to USDA + Swift math.
struct ParsedFoodItem: Codable, Sendable, Equatable {
    let raw: String           // echo of input
    let food: String          // USDA-search-friendly canonical name
    let grams: Double         // weight in grams (model converts cups/oz/tbsp)
    let state: String         // "raw" | "cooked" | "unspecified"
    let preparation: String?  // "grilled" | "boiled" | "fried" | nil
    let confidence: String    // "high" | "medium" | "low"
    let ambiguityNote: String?
}

private struct ParsedFoodEnvelope: Codable, Sendable {
    let items: [ParsedFoodItem]
}

// MARK: - USDA result type

struct USDAFoodResult: Sendable, Equatable {
    let fdcId: Int
    let description: String
    let dataType: String   // "Foundation" | "SR Legacy"
    let kcalPer100g: Double
    let proteinPer100g: Double
    let fatPer100g: Double
    let carbsPer100g: Double
}

// MARK: - Errors

enum MealCalculatorError: LocalizedError {
    case noItems
    case tooManyItems(Int, max: Int)
    case innerLLMFailed(String)
    case innerLLMInvalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .noItems:
            return "calculate_meal requires at least one item"
        case .tooManyItems(let count, let max):
            return "calculate_meal received \(count) items but the maximum is \(max)"
        case .innerLLMFailed(let message):
            return "Inner LLM call failed: \(message)"
        case .innerLLMInvalidJSON(let message):
            return "Inner LLM returned invalid JSON: \(message)"
        }
    }
}

// MARK: - Calculator

/// Pipeline:
/// 1. Inner LLM (gpt-4o-mini via OpenRouter) — parse natural-language items
///    into structured `ParsedFoodItem` rows (food name, grams, state).
/// 2. USDA FoodData Central — parallel lookup of per-100g raw nutrition.
/// 3. Swift math — apply cooked → raw correction (if any) and scale to the
///    raw-equivalent grams to get final kcal / protein / fat / carbs.
///
/// All operations are done on the main actor for SwiftUI affinity, but the
/// USDA fan-out uses `URLSession` which hops off-actor automatically. We
/// cache successful per-item results in memory so repeat lookups (e.g. the
/// coach asking about the same staple meal twice) skip both calls.
@MainActor
final class MealCalculator {
    static let schemaVersion = "calculate-meal-v1"
    static let maxItems = 20

    private let openRouterClient: CoachOpenRouterClient
    private let usdaAPIKeyProvider: () -> String
    private let urlSession: URLSession
    private let now: () -> Date

    private var cache: [String: CalculatedFoodItem] = [:]

    init(
        openRouterClient: CoachOpenRouterClient,
        usdaAPIKeyProvider: @escaping () -> String = { USDACredentialStore.apiKey },
        urlSession: URLSession = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.openRouterClient = openRouterClient
        self.usdaAPIKeyProvider = usdaAPIKeyProvider
        self.urlSession = urlSession
        self.now = now
    }

    /// Compute kcal/protein/fat/carbs for each item plus the meal total.
    /// `assumeRawWhenAmbiguous` is forwarded to the inner LLM via the system
    /// prompt; the default mirrors the more conservative interpretation
    /// (raw weights tend to imply higher cooked yields, which keeps coach
    /// recommendations from over-counting).
    func calculate(
        items rawItems: [String],
        assumeRawWhenAmbiguous: Bool = true
    ) async throws -> CalculateMealResult {
        // Trim and split out items already in the cache so we only spend tokens
        // and USDA quota on the new work.
        let trimmed = rawItems
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { throw MealCalculatorError.noItems }
        guard trimmed.count <= Self.maxItems else {
            throw MealCalculatorError.tooManyItems(trimmed.count, max: Self.maxItems)
        }

        // Resolve cache hits by normalized key (lowercase + trim).
        var resolved: [Int: CalculatedFoodItem] = [:]
        var pendingIndices: [Int] = []
        var pendingItems: [String] = []
        for (idx, item) in trimmed.enumerated() {
            let key = Self.cacheKey(item)
            if let cached = cache[key] {
                resolved[idx] = CalculatedFoodItem(
                    input: cached.input,
                    food: cached.food,
                    fdcId: cached.fdcId,
                    dataType: cached.dataType,
                    grams: cached.grams,
                    rawEquivalentGrams: cached.rawEquivalentGrams,
                    state: cached.state,
                    stateAdjustment: cached.stateAdjustment,
                    kcal: cached.kcal,
                    proteinG: cached.proteinG,
                    fatG: cached.fatG,
                    carbsG: cached.carbsG,
                    confidence: cached.confidence,
                    source: "cache",
                    warnings: cached.warnings
                )
            } else {
                pendingIndices.append(idx)
                pendingItems.append(item)
            }
        }

        // 1) Inner-LLM parse for the pending items.
        var parsedByIndex: [Int: ParsedFoodItem] = [:]
        if !pendingItems.isEmpty {
            let parsed = try await parseFood(items: pendingItems, assumeRawWhenAmbiguous: assumeRawWhenAmbiguous)
            // The inner model is asked to echo `raw` so we can align by input;
            // fall back to positional matching if that breaks down.
            for (offset, idx) in pendingIndices.enumerated() {
                let input = pendingItems[offset]
                let match = parsed.first { $0.raw == input } ?? (offset < parsed.count ? parsed[offset] : nil)
                if let match {
                    parsedByIndex[idx] = match
                }
            }
        }

        // 2) Parallel USDA lookups. Failures are tolerated per-item.
        let lookups: [Int: Result<USDAFoodResult?, Error>] = await withTaskGroup(
            of: (Int, Result<USDAFoodResult?, Error>).self
        ) { group in
            for (idx, parsed) in parsedByIndex {
                let key = usdaAPIKeyProvider()
                let session = urlSession
                let foodQuery = parsed.food
                group.addTask {
                    do {
                        let result = try await Self.lookupUSDA(
                            query: foodQuery,
                            apiKey: key,
                            session: session
                        )
                        return (idx, .success(result))
                    } catch {
                        return (idx, .failure(error))
                    }
                }
            }
            var out: [Int: Result<USDAFoodResult?, Error>] = [:]
            for await (idx, result) in group {
                out[idx] = result
            }
            return out
        }

        // 3) Compose final items in order.
        var aggregateWarnings: [String] = []
        var finalItems: [CalculatedFoodItem] = []
        for idx in trimmed.indices {
            if let cached = resolved[idx] {
                finalItems.append(cached)
                continue
            }
            let input = trimmed[idx]
            guard let parsed = parsedByIndex[idx] else {
                let item = CalculatedFoodItem.unavailable(input: input, reason: "could not parse food")
                aggregateWarnings.append("Could not parse '\(input)'.")
                finalItems.append(item)
                continue
            }

            let usdaResult = lookups[idx] ?? .success(nil)
            switch usdaResult {
            case .failure(let error):
                let item = CalculatedFoodItem.unavailable(
                    input: input,
                    parsed: parsed,
                    reason: "usda lookup failed: \(error.localizedDescription)"
                )
                aggregateWarnings.append("USDA lookup failed for '\(parsed.food)'.")
                finalItems.append(item)
            case .success(nil):
                let item = CalculatedFoodItem.unavailable(
                    input: input,
                    parsed: parsed,
                    reason: "no USDA match"
                )
                aggregateWarnings.append("No USDA match for '\(parsed.food)'.")
                finalItems.append(item)
            case .success(let usda?):
                let computed = compose(input: input, parsed: parsed, usda: usda)
                if computed.confidence != "unavailable" {
                    cache[Self.cacheKey(input)] = computed
                }
                if let note = parsed.ambiguityNote, !note.isEmpty {
                    aggregateWarnings.append("\(parsed.food): \(note)")
                }
                finalItems.append(computed)
            }
        }

        // Total only sums items where we landed on real numbers.
        var totalKcal = 0
        var totalProtein = 0.0
        var totalFat = 0.0
        var totalCarbs = 0.0
        for item in finalItems where item.confidence != "unavailable" {
            totalKcal += item.kcal
            totalProtein += item.proteinG
            totalFat += item.fatG
            totalCarbs += item.carbsG
        }

        return CalculateMealResult(
            items: finalItems,
            total: MacroTotals(
                kcal: totalKcal,
                proteinG: roundedGrams(totalProtein),
                fatG: roundedGrams(totalFat),
                carbsG: roundedGrams(totalCarbs)
            ),
            warnings: aggregateWarnings,
            schemaVersion: Self.schemaVersion
        )
    }

    // MARK: - Inner LLM

    /// System prompt for the inner parser. Treated as a constant so audit
    /// traces can be reproduced without re-reading source.
    static let innerSystemPrompt: String = """
    You extract structured food information from natural language descriptions.
    Output ONLY valid JSON matching this schema: {"items": [...]}

    For each food item, produce:
    - "raw": exact input string (echo)
    - "food": USDA-search-friendly canonical name (e.g. "chicken breast, skinless, boneless" not "chicken")
    - "grams": weight in grams (convert from cups/oz/tbsp using these references: 1 cup white rice uncooked=185g, 1 cup cooked rice=186g, 1 cup oats=90g, 1 tbsp olive oil=13.5g, 1 oz=28.35g)
    - "state": "raw" | "cooked" | "unspecified"
    - "preparation": cooking method if specified ("grilled", "boiled", "fried", null if not specified)
    - "confidence": "high" if clear, "medium" if estimated, "low" if very ambiguous
    - "ambiguityNote": explain ambiguity if confidence is medium/low, null otherwise

    Do NOT estimate calories, protein, fat, or carbs. Another system computes those.
    Assume raw when ambiguous unless the item is clearly described as cooked.
    """

    /// Run the inner LLM through OpenRouter. Mirrors `CoachOpenRouterClient`
    /// transport but skips tool calling — we just want a JSON object back.
    func parseFood(items: [String], assumeRawWhenAmbiguous: Bool) async throws -> [ParsedFoodItem] {
        guard let key = OpenRouterCredentialStore.loadAPIKey(), !key.isEmpty else {
            throw MealCalculatorError.innerLLMFailed("No OpenRouter key is connected")
        }

        var systemPrompt = Self.innerSystemPrompt
        if !assumeRawWhenAmbiguous {
            systemPrompt += "\nWhen state is ambiguous, prefer 'cooked' instead of 'raw'."
        }

        let body: [String: Any] = [
            "model": "openai/gpt-4o-mini",
            "temperature": 0.0,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": items.joined(separator: "\n")]
            ],
            "metadata": [
                "feature": "coach.calculate_meal.parse"
            ]
        ]

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("WeightTracker", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let start = Date()
        let (data, response) = try await urlSession.data(for: request)
        let latencyMs = Int(Date().timeIntervalSince(start) * 1000)

        guard let http = response as? HTTPURLResponse else {
            throw MealCalculatorError.innerLLMFailed("missing HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let preview = String(data: data, encoding: .utf8).map { String($0.prefix(500)) } ?? ""
            throw MealCalculatorError.innerLLMFailed("HTTP \(http.statusCode): \(preview)")
        }

        guard let top = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MealCalculatorError.innerLLMInvalidJSON("response is not JSON")
        }

        // Cost ledger: keep the inner call separately so it shows up in usage.
        if let usageRaw = top["usage"] {
            let usageData = try? JSONSerialization.data(withJSONObject: usageRaw)
            let usage = usageData.flatMap { try? JSONDecoder().decode(OpenRouterUsagePayload.self, from: $0) }
            let modelUsed = (top["model"] as? String) ?? "openai/gpt-4o-mini"
            CostLedger.shared.log(
                feature: "coach.calculate_meal.parse",
                model: modelUsed,
                usage: usage,
                latencyMs: latencyMs
            )
        }

        guard
            let choices = top["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw MealCalculatorError.innerLLMInvalidJSON("missing choices[0].message.content")
        }

        let envelopeData = Data(content.utf8)
        do {
            let envelope = try JSONDecoder().decode(ParsedFoodEnvelope.self, from: envelopeData)
            return envelope.items
        } catch {
            throw MealCalculatorError.innerLLMInvalidJSON(error.localizedDescription)
        }
    }

    // MARK: - USDA

    /// Hit USDA FoodData Central's `/foods/search` and return the best match,
    /// preferring Foundation entries over SR Legacy.
    ///
    /// `nonisolated` because we call this from inside a task group; it doesn't
    /// touch any actor state and only uses the captured `URLSession`.
    nonisolated static func lookupUSDA(
        query: String,
        apiKey: String,
        session: URLSession = .shared,
        timeoutSeconds: TimeInterval = 10
    ) async throws -> USDAFoodResult? {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy"),
            URLQueryItem(name: "pageSize", value: "5"),
            URLQueryItem(name: "nutrients", value: "1003,1004,1005,1008")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeoutSeconds

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw error
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }
        // 429 is the rate limit response when DEMO_KEY runs out. We surface
        // it as an error so the caller can mark the item unavailable.
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProviderError.http(status: http.statusCode, body: body)
        }

        guard
            let top = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let foods = top["foods"] as? [[String: Any]]
        else {
            return nil
        }

        // Prefer Foundation entries, then SR Legacy. Keep the first match in
        // each bucket — USDA already returns relevance-ranked results.
        let foundation = foods.first { ($0["dataType"] as? String) == "Foundation" }
        let srLegacy = foods.first { ($0["dataType"] as? String) == "SR Legacy" }
        let chosen = foundation ?? srLegacy ?? foods.first

        guard let chosen else { return nil }

        let fdcId = (chosen["fdcId"] as? Int) ?? Int(chosen["fdcId"] as? Double ?? 0)
        let description = (chosen["description"] as? String) ?? query
        let dataType = (chosen["dataType"] as? String) ?? "unknown"
        let nutrients = (chosen["foodNutrients"] as? [[String: Any]]) ?? []

        // Always look up by nutrientId, never by index. USDA does not
        // guarantee ordering and may omit nutrients entirely for some entries.
        let kcal = nutrientValue(nutrients, id: 1008) ?? 0
        let protein = nutrientValue(nutrients, id: 1003) ?? 0
        let fat = nutrientValue(nutrients, id: 1004) ?? 0
        let carbs = nutrientValue(nutrients, id: 1005) ?? 0

        return USDAFoodResult(
            fdcId: fdcId,
            description: description,
            dataType: dataType,
            kcalPer100g: kcal,
            proteinPer100g: protein,
            fatPer100g: fat,
            carbsPer100g: carbs
        )
    }

    /// Pull a nutrient value out of a USDA `foodNutrients` array by stable id.
    /// USDA exposes the value under a few different shapes depending on which
    /// search endpoint you hit; we accept the common ones.
    nonisolated private static func nutrientValue(_ nutrients: [[String: Any]], id: Int) -> Double? {
        for n in nutrients {
            // Search-result shape: { "nutrientId": 1008, "value": 120.0, ... }
            if let nid = n["nutrientId"] as? Int, nid == id {
                if let v = n["value"] as? Double { return v }
                if let v = n["value"] as? Int { return Double(v) }
                if let v = n["amount"] as? Double { return v }
            }
            // Detail-result shape: { "nutrient": { "id": 1008 }, "amount": 120.0 }
            if let nested = n["nutrient"] as? [String: Any],
               let nid = nested["id"] as? Int, nid == id {
                if let v = n["amount"] as? Double { return v }
                if let v = n["amount"] as? Int { return Double(v) }
            }
        }
        return nil
    }

    // MARK: - Composition

    /// Convert a parsed item + USDA per-100g values into a CalculatedFoodItem.
    /// Applies the cooked → raw correction when the user reported cooked
    /// weight and we can detect a known food class.
    private func compose(input: String, parsed: ParsedFoodItem, usda: USDAFoodResult) -> CalculatedFoodItem {
        var warnings: [String] = []
        var rawEquivalentGrams = parsed.grams
        var adjustment: CookingAdjustmentInfo? = nil

        if parsed.state.lowercased() == "cooked" {
            if let foodClass = CookingStateAdjustments.detect(from: parsed.food),
               let adj = CookingStateAdjustments.adjustment(for: foodClass) {
                rawEquivalentGrams = parsed.grams * adj.cookedToRawFactor
                adjustment = CookingAdjustmentInfo(
                    fromState: "cooked",
                    toState: "raw-equivalent",
                    factor: adj.cookedToRawFactor,
                    rule: adj.rule
                )
            } else {
                warnings.append("'\(parsed.food)' was reported cooked but no raw conversion is known; using cooked grams as raw")
            }
        }

        let scale = rawEquivalentGrams / 100.0
        let kcal = Int((usda.kcalPer100g * scale).rounded())
        let protein = roundedGrams(usda.proteinPer100g * scale)
        let fat = roundedGrams(usda.fatPer100g * scale)
        let carbs = roundedGrams(usda.carbsPer100g * scale)

        let confidence: String = {
            // Promote LLM "low" / "medium" through, USDA always counts as
            // high-quality data when we land a Foundation/SR Legacy match.
            if usda.kcalPer100g <= 0 && usda.proteinPer100g <= 0 {
                return "low"
            }
            return parsed.confidence
        }()

        return CalculatedFoodItem(
            input: input,
            food: parsed.food,
            fdcId: usda.fdcId,
            dataType: usda.dataType,
            grams: parsed.grams,
            rawEquivalentGrams: rawEquivalentGrams,
            state: parsed.state,
            stateAdjustment: adjustment,
            kcal: kcal,
            proteinG: protein,
            fatG: fat,
            carbsG: carbs,
            confidence: confidence,
            source: "usda-fdc",
            warnings: warnings
        )
    }

    // MARK: - Helpers

    private static func cacheKey(_ item: String) -> String {
        item.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func roundedGrams(_ value: Double) -> Double {
        // 1 decimal — kept as Double in case the coach wants finer granularity
        // for protein totals, but rounded to keep audit JSON tidy.
        (value * 10).rounded() / 10
    }
}

private extension CalculatedFoodItem {
    /// Helper for items that couldn't be priced (no USDA hit, parse fail, etc.).
    /// We still echo the input so the coach can present a complete meal list.
    static func unavailable(input: String, parsed: ParsedFoodItem? = nil, reason: String) -> CalculatedFoodItem {
        CalculatedFoodItem(
            input: input,
            food: parsed?.food ?? input,
            fdcId: nil,
            dataType: nil,
            grams: parsed?.grams ?? 0,
            rawEquivalentGrams: parsed?.grams ?? 0,
            state: parsed?.state ?? "unspecified",
            stateAdjustment: nil,
            kcal: 0,
            proteinG: 0,
            fatG: 0,
            carbsG: 0,
            confidence: "unavailable",
            source: "usda-fdc",
            warnings: [reason]
        )
    }
}
