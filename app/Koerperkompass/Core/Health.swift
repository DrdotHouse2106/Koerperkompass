import Foundation
import HealthKit

/// Zugriff auf Apple Health. Die App funktioniert auch ohne Freigabe – dann liefern die Abfragen einfach nichts.
enum Health {
    static let store = HKHealthStore()
    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKQuantityType(.restingHeartRate),
        HKQuantityType(.bodyMass), HKCategoryType(.sleepAnalysis), HKObjectType.workoutType(),
    ]
    static let writeTypes: Set<HKSampleType> = [
        HKQuantityType(.bodyMass), HKQuantityType(.dietaryEnergyConsumed), HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates), HKQuantityType(.dietaryFatTotal),
    ]

    static func authorize() async throws {
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    private static func since(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: Date()))!
    }

    /// Tageswerte (Summe oder Durchschnitt) einer Messgröße
    private static func daily(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, sum: Bool, days: Int) async -> [String: Double] {
        let start = since(days)
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: start, end: nil)),
            options: sum ? .cumulativeSum : .discreteAverage, anchorDate: start, intervalComponents: DateComponents(day: 1))
        guard let result = try? await query.result(for: store) else { return [:] }
        var out: [String: Double] = [:]
        result.enumerateStatistics(from: start, to: Date()) { s, _ in
            if let q = sum ? s.sumQuantity() : s.averageQuantity() { out[Day.string(s.startDate)] = q.doubleValue(for: unit) }
        }
        return out
    }

    /// Aktivität und Schlaf der letzten Tage: Tag → Feldwerte des Moduls „activity“
    static func activity(days: Int) async -> [String: [String: Double]] {
        var out: [String: [String: Double]] = [:]
        func add(_ key: String, _ values: [String: Double]) {
            for (day, v) in values { out[day, default: [:]][key] = (v * 10).rounded() / 10 }
        }
        add("steps", await daily(.stepCount, .count(), sum: true, days: days))
        add("activeEnergy", await daily(.activeEnergyBurned, .kilocalorie(), sum: true, days: days))
        add("restingHR", await daily(.restingHeartRate, .count().unitDivided(by: .minute()), sum: false, days: days))

        let p = HKQuery.predicateForSamples(withStart: since(days), end: nil)
        let asleep = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        let sleep = (try? await HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: p)], sortDescriptors: []).result(for: store)) ?? []
        var hours: [String: Double] = [:]
        for s in sleep where asleep.contains(s.value) {
            hours[Day.string(s.endDate), default: 0] += s.endDate.timeIntervalSince(s.startDate) / 3600
        }
        add("sleepHours", hours)

        let workouts = (try? await HKSampleQueryDescriptor(predicates: [.workout(p)], sortDescriptors: []).result(for: store)) ?? []
        var minutes: [String: Double] = [:]
        for w in workouts { minutes[Day.string(w.endDate), default: 0] += w.duration / 60 }
        add("workoutMinutes", minutes)
        return out
    }

    /// Gewichtsmessungen anderer Apps/Waagen (eigene Einträge der App werden übersprungen)
    static func weights(days: Int) async -> [(id: String, date: String, kg: Double)] {
        let p = HKQuery.predicateForSamples(withStart: since(days), end: nil)
        let samples = (try? await HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: p)], sortDescriptors: []).result(for: store)) ?? []
        return samples
            .filter { $0.sourceRevision.source != HKSource.default() }
            .map { ("health-" + $0.uuid.uuidString, Day.string($0.endDate), ($0.quantity.doubleValue(for: .gramUnit(with: .kilo)) * 10).rounded() / 10) }
    }

    /// Durchschnittliche aktive Energie pro Tag (letzte 14 Tage), nil ohne Daten
    static func averageActiveEnergy() async -> Double? {
        let values = await daily(.activeEnergyBurned, .kilocalorie(), sum: true, days: 14).values.filter { $0 > 0 }
        return values.count >= 3 ? values.reduce(0, +) / Double(values.count) : nil
    }

    static func saveWeight(_ kg: Double) {
        let s = HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg), start: Date(), end: Date())
        store.save(s) { _, _ in }
    }

    static func saveMeal(name: String, kcal: Double, protein: Double, carbs: Double, fat: Double) {
        let meta = [HKMetadataKeyFoodType: name]
        let values: [(HKQuantityTypeIdentifier, HKUnit, Double)] = [
            (.dietaryEnergyConsumed, .kilocalorie(), kcal), (.dietaryProtein, .gram(), protein),
            (.dietaryCarbohydrates, .gram(), carbs), (.dietaryFatTotal, .gram(), fat),
        ]
        let samples: [HKSample] = values.filter { $0.2 > 0 }.map {
            HKQuantitySample(type: HKQuantityType($0.0), quantity: HKQuantity(unit: $0.1, doubleValue: $0.2), start: Date(), end: Date(), metadata: meta)
        }
        if !samples.isEmpty { store.save(samples) { _, _ in } }
    }
}
