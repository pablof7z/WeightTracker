import Foundation

public enum WeightUnit: String, Codable, CaseIterable, Sendable {
    case lbs, kg
    public var symbol: String { self == .lbs ? "lb" : "kg" }
    public var label: String { self == .lbs ? "Pounds" : "Kilograms" }
}

public enum BodyUnit: String, Codable, CaseIterable, Sendable {
    case inches, cm
    public var symbol: String { self == .inches ? "in" : "cm" }
    public var label: String { self == .inches ? "Inches" : "Centimeters" }
}

public enum ThemePreference: String, Codable, CaseIterable, Sendable {
    case system, light, dark
    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

public enum UnitConvert {
    public static let kgPerLb: Double = 0.45359237
    public static let cmPerInch: Double = 2.54

    public static func kgToLb(_ kg: Double) -> Double { kg / kgPerLb }
    public static func lbToKg(_ lb: Double) -> Double { lb * kgPerLb }
    public static func cmToInch(_ cm: Double) -> Double { cm / cmPerInch }
    public static func inchToCm(_ inch: Double) -> Double { inch * cmPerInch }

    public static func displayWeight(kg: Double, in unit: WeightUnit) -> Double {
        unit == .lbs ? kgToLb(kg) : kg
    }

    public static func storeWeight(_ value: Double, from unit: WeightUnit) -> Double {
        unit == .lbs ? lbToKg(value) : value
    }

    public static func displayBody(cm: Double, in unit: BodyUnit) -> Double {
        unit == .inches ? cmToInch(cm) : cm
    }

    public static func storeBody(_ value: Double, from unit: BodyUnit) -> Double {
        unit == .inches ? inchToCm(value) : value
    }
}

public extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let m = pow(10.0, Double(places))
        return (self * m).rounded() / m
    }
}
