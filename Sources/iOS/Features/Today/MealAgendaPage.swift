import Foundation

extension Notification.Name {
    /// Posted when the user taps "Edit plan" in the meal-plan UI. The Cuts tab
    /// observes this and routes to the meal-plan editor.
    static let openMealPlanEditor = Notification.Name("openMealPlanEditor")
}

/// Shared meal-slot time formatting, used by `MealPlanCard` and `MealPlanDetail`.
enum MealAgendaPage {
    /// Locale-aware short time formatter (respects the user's 12/24h preference).
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    /// Convert minutes-from-midnight to a `Date` anchored on today, then format.
    static func timeString(fromMinutesFromMidnight minutes: Int) -> String {
        let cal = Calendar.current
        let h = max(0, min(23, minutes / 60))
        let m = max(0, min(59, minutes % 60))
        let date = cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
        return timeFormatter.string(from: date)
    }
}
