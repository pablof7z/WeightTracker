import Foundation

/// Coarse classes of food the calculator knows how to convert from "cooked
/// grams" to "raw-equivalent grams". Used to apply a deterministic correction
/// factor on top of USDA per-100g raw values.
enum FoodClass: String, CaseIterable, Sendable {
    case chickenBreast
    case chickenThigh
    case beefGround
    case beefSteak
    case porkLean
    case fishWhite
    case salmon
    case shrimp
    case eggs
    case riceWhite
    case riceBrown
    case riceBasmati
    case pasta
    case quinoa
    case oats
    case lentils
    case beans
    case potatoes
    case vegetablesSteamed
}

/// One row in the cooked → raw conversion table.
///
/// `cookedToRawFactor` is the multiplier applied to a *cooked weight in
/// grams* to get the *raw-equivalent weight in grams*. So:
///
///   raw_equivalent_g = cooked_g × factor
///
/// USDA Foundation/SR Legacy entries we look up are quoted per 100g raw, so
/// the calculator multiplies `(raw_equivalent_g / 100) × kcalPer100g` to land
/// on the kcal for that meal item.
struct CookingAdjustment: Sendable, Equatable {
    let foodClass: FoodClass
    let cookedToRawFactor: Double

    /// Stable rule identifier used in audit JSON so we can later evolve the
    /// table without breaking historical traces.
    var rule: String { "\(foodClass.rawValue)-cooked-to-raw" }
}

enum CookingStateAdjustments {
    /// Static cooked → raw factors. Numbers are conservative midpoints from
    /// USDA cooking yield tables.
    ///
    /// - Proteins lose water on cooking (factor < 1.0).
    /// - Grains/legumes absorb water on cooking (factor << 1.0).
    /// - Vegetables only shed a little water (factor near 1.0).
    static let table: [FoodClass: Double] = [
        .chickenBreast: 0.75,   // chicken breast loses ~25% water when grilled/baked
        .chickenThigh: 0.78,
        .beefGround: 0.72,      // ground beef loses ~28% (water + rendered fat)
        .beefSteak: 0.75,
        .porkLean: 0.75,
        .fishWhite: 0.80,       // cod, tilapia, etc.
        .salmon: 0.78,
        .shrimp: 0.78,
        .eggs: 0.90,            // eggs barely lose mass when scrambled/boiled
        .riceWhite: 0.333,      // 1 cup cooked rice ≈ 1/3 cup raw rice
        .riceBasmati: 0.333,
        .riceBrown: 0.36,
        .pasta: 0.40,
        .quinoa: 0.333,
        .oats: 0.45,
        .lentils: 0.40,
        .beans: 0.38,
        .potatoes: 0.95,
        .vegetablesSteamed: 0.85
    ]

    static func adjustment(for foodClass: FoodClass) -> CookingAdjustment? {
        guard let factor = table[foodClass] else { return nil }
        return CookingAdjustment(foodClass: foodClass, cookedToRawFactor: factor)
    }

    /// Best-effort detection from a USDA-style food name. Specificity wins:
    /// "chicken breast" must match before the bare "chicken" check, and
    /// basmati before rice, etc. Returns nil when the food doesn't fit any
    /// known class — callers should treat that as "no correction".
    static func detect(from foodName: String) -> FoodClass? {
        let s = foodName.lowercased()

        // Order matters: more specific before less specific.
        if s.contains("chicken breast") { return .chickenBreast }
        if s.contains("chicken thigh") || s.contains("chicken leg") { return .chickenThigh }
        if s.contains("ground beef") || s.contains("beef mince") || s.contains("minced beef") {
            return .beefGround
        }
        if s.contains("steak") || s.contains("ribeye") || s.contains("sirloin") || s.contains("beef tender") {
            return .beefSteak
        }
        if s.contains("pork loin") || s.contains("pork tender") || s.contains("lean pork") {
            return .porkLean
        }
        if s.contains("salmon") { return .salmon }
        if s.contains("shrimp") || s.contains("prawn") { return .shrimp }
        if s.contains("cod") || s.contains("tilapia") || s.contains("haddock")
            || s.contains("white fish") || s.contains("whitefish") {
            return .fishWhite
        }
        if s.contains("egg") { return .eggs }

        if s.contains("basmati") { return .riceBasmati }
        if s.contains("brown rice") { return .riceBrown }
        if s.contains("white rice") || s.contains("jasmine") || s.contains("rice") {
            return .riceWhite
        }

        if s.contains("pasta") || s.contains("spaghetti") || s.contains("penne")
            || s.contains("macaroni") || s.contains("noodle") {
            return .pasta
        }
        if s.contains("quinoa") { return .quinoa }
        if s.contains("oats") || s.contains("oatmeal") || s.contains("porridge") {
            return .oats
        }
        if s.contains("lentil") { return .lentils }
        if s.contains("bean") || s.contains("chickpea") || s.contains("garbanzo") {
            return .beans
        }
        if s.contains("potato") { return .potatoes }
        if s.contains("steamed") || s.contains("broccoli") || s.contains("spinach")
            || s.contains("kale") || s.contains("zucchini") || s.contains("courgette")
            || s.contains("cauliflower") || s.contains("asparagus") {
            return .vegetablesSteamed
        }

        return nil
    }
}
