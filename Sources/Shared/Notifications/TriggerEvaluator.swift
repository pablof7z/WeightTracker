import Foundation

public enum TriggerEvaluator {
    public static func evaluateTriggers(
        readings: [Reading],
        now: Date = Date(),
        preferences: NotificationPreferences
    ) -> [ScheduledTrigger] {
        guard preferences.master else { return [] }
        var out: [ScheduledTrigger] = []

        guard let last = readings.last else { return [] }
        let daysSince = max(0, Calendar.current.dateComponents([.day], from: last.date, to: now).day ?? 0)

        // Gap forming: 7 days
        if preferences.gapForming, daysSince == 7 {
            out.append(ScheduledTrigger(
                id: "gap.forming",
                title: "Gap forming",
                body: "You haven't logged in a week. Based on your history, you're 14 days from a typical drift gap.",
                fireAfter: nextAllowedFire(after: now, prefs: preferences)
            ))
        }
        // Gap deepening: 30 days
        if preferences.gapDeepening, daysSince == 30 {
            let lastWeightLb = UnitConvert.kgToLb(last.weightKg)
            let estimate = lastWeightLb + 1.2
            out.append(ScheduledTrigger(
                id: "gap.deepening",
                title: "It's been a month",
                body: String(format: "Average drift in 30+ day gaps is +1.2 lb/month — you're probably around %.1f today.", estimate),
                fireAfter: nextAllowedFire(after: now, prefs: preferences)
            ))
        }
        // Cluster broken
        if preferences.clusterBroken, isClusterBroken(readings: readings, now: now) {
            out.append(ScheduledTrigger(
                id: "cluster.broken",
                title: "Tracking streak ended",
                body: "Your tracking streak ended. Don't let this become a gap — quick log?",
                fireAfter: nextAllowedFire(after: now, prefs: preferences)
            ))
        }
        // Cut-related
        if let cut = ActiveCutStore.load() {
            // Cut day reminder
            if preferences.cutDay {
                if let fire = nextDailyFire(at: cut.dailyReminderSecondsAfterMidnight, after: now, prefs: preferences) {
                    let day = cut.daysElapsed(now: now) + 1
                    out.append(ScheduledTrigger(
                        id: "cut.day",
                        title: "Cut day \(day) of \(cut.totalDays)",
                        body: "Quick log?",
                        fireAfter: fire
                    ))
                }
            }
            // Milestones
            if preferences.cutMilestone, let r = readings.last(where: { $0.date <= now }) {
                let totalLossKg = cut.totalLossKg
                let actualLossKg = cut.startWeightKg - r.weightKg
                let percent = totalLossKg > 0 ? actualLossKg / totalLossKg : 0
                let milestoneHit: Int? = [25, 50, 75, 100].first { abs(percent * 100 - Double($0)) < 2.5 }
                if let m = milestoneHit {
                    let downLb = UnitConvert.kgToLb(actualLossKg)
                    let toGoLb = UnitConvert.kgToLb(totalLossKg - actualLossKg)
                    out.append(ScheduledTrigger(
                        id: "cut.milestone.\(m)",
                        title: "\(m)% there",
                        body: String(format: "%.1f lbs down, %.1f to go.", downLb, max(0, toGoLb)),
                        fireAfter: nextAllowedFire(after: now, prefs: preferences)
                    ))
                }
            }
            // Stall
            if preferences.cutStall, isCutStalled(cut: cut, readings: readings, now: now) {
                out.append(ScheduledTrigger(
                    id: "cut.stall",
                    title: "Possible stall",
                    body: "Your 14-day average is up. Worth checking in.",
                    fireAfter: nextAllowedFire(after: now, prefs: preferences)
                ))
            }
        }

        return out
    }

    private static func isClusterBroken(readings: [Reading], now: Date) -> Bool {
        guard readings.count >= 6 else { return false }
        let recent = readings.suffix(6)
        let last = recent.last!
        let prior = Array(recent.dropLast())
        var gaps: [Int] = []
        var previous: Date? = nil
        for r in prior {
            if let p = previous {
                gaps.append(Calendar.current.dateComponents([.day], from: p, to: r.date).day ?? 0)
            }
            previous = r.date
        }
        let avg = gaps.isEmpty ? 0 : Double(gaps.reduce(0, +)) / Double(gaps.count)
        let daysSinceLast = Calendar.current.dateComponents([.day], from: last.date, to: now).day ?? 0
        return avg < 3 && daysSinceLast >= 3 && daysSinceLast < 7
    }

    private static func isCutStalled(cut: ActiveCut, readings: [Reading], now: Date) -> Bool {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        let recent = readings.filter { $0.date >= cutoff && $0.date >= cut.startDate }
        guard recent.count >= 3, let first = recent.first, let last = recent.last else { return false }
        return last.weightKg > first.weightKg + 0.27 // ~0.6 lb
    }

    private static func nextAllowedFire(after now: Date, prefs: NotificationPreferences) -> TimeInterval {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        if isQuietHour(hour: hour, prefs: prefs) {
            // Schedule for end of quiet
            var next = cal.dateComponents([.year, .month, .day], from: now)
            next.hour = prefs.quietEndHour
            next.minute = 0
            next.second = 0
            if hour >= prefs.quietStartHour {
                let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
                next = cal.dateComponents([.year, .month, .day], from: tomorrow)
                next.hour = prefs.quietEndHour
                next.minute = 0
            }
            let target = cal.date(from: next) ?? now.addingTimeInterval(3600)
            return max(1, target.timeIntervalSince(now))
        }
        return 1
    }

    private static func nextDailyFire(at secondsAfterMidnight: Int, after now: Date, prefs: NotificationPreferences) -> TimeInterval? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        guard var fire = cal.date(byAdding: .second, value: secondsAfterMidnight, to: start) else { return nil }
        if fire <= now {
            fire = cal.date(byAdding: .day, value: 1, to: fire) ?? fire
        }
        return max(1, fire.timeIntervalSince(now))
    }

    private static func isQuietHour(hour: Int, prefs: NotificationPreferences) -> Bool {
        if prefs.quietStartHour == prefs.quietEndHour { return false }
        if prefs.quietStartHour < prefs.quietEndHour {
            return hour >= prefs.quietStartHour && hour < prefs.quietEndHour
        } else {
            return hour >= prefs.quietStartHour || hour < prefs.quietEndHour
        }
    }
}
