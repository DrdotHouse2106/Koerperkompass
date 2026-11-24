import Foundation
import HealthKit

/// Zugriff auf Apple Health. Die App funktioniert auch ohne Freigabe – dann liefern die Abfragen einfach nichts.
enum Health {
    static let store = HKHealthStore()
    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    static var readTypes: Set<HKObjectType> {
        var t = baseRead.union(symptomTypes)
        if #available(iOS 18.0, *) { t.insert(HKSampleType.stateOfMindType()) }  // Gemütszustand (Stimmung)
        return t
    }
    static var writeTypes: Set<HKSampleType> {
        var t = baseWrite.union(symptomTypes)
        if #available(iOS 18.0, *) { t.insert(HKSampleType.stateOfMindType()) }
        return t
    }

    private static let baseRead: Set<HKObjectType> = [
        HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKQuantityType(.restingHeartRate),
        HKQuantityType(.bodyMass), HKCategoryType(.sleepAnalysis), HKObjectType.workoutType(),
        HKQuantityType(.bodyFatPercentage), HKQuantityType(.leanBodyMass),  // Körperfettwaagen (über deren App nach Health)
    ]
    private static let baseWrite: Set<HKSampleType> = [
        HKQuantityType(.bodyMass), HKQuantityType(.dietaryEnergyConsumed), HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates), HKQuantityType(.dietaryFatTotal),
        HKQuantityType(.dietaryWater), HKQuantityType(.dietaryCaffeine), HKQuantityType(.numberOfAlcoholicBeverages),
        HKObjectType.workoutType(),
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

    /// Körpermessungen anderer Apps/Waagen: Gewicht, dazu Körperfett und fettfreie Masse derselben Messung
    /// (eigene Einträge der App werden übersprungen). Eine Messung = ein Eintrag, verbunden über den Zeitpunkt (±2 min).
    static func bodyMeasurements(days: Int) async -> [(id: String, date: String, values: [String: Any])] {
        let p = HKQuery.predicateForSamples(withStart: since(days), end: nil)
        func samples(_ id: HKQuantityTypeIdentifier) async -> [HKQuantitySample] {
            ((try? await HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(id), predicate: p)], sortDescriptors: []).result(for: store)) ?? [])
                .filter { $0.sourceRevision.source != HKSource.default() }
        }
        let kg = HKUnit.gramUnit(with: .kilo)
        let weights = await samples(.bodyMass), fats = await samples(.bodyFatPercentage), leans = await samples(.leanBodyMass)
        func near(_ list: [HKQuantitySample], _ d: Date) -> HKQuantitySample? { list.first { abs($0.endDate.timeIntervalSince(d)) < 120 } }
        var out: [(id: String, date: String, values: [String: Any])] = []
        var used = Set<UUID>()
        for w in weights {
            var v: [String: Any] = ["weight": (w.quantity.doubleValue(for: kg) * 10).rounded() / 10]
            if let f = near(fats, w.endDate) { v["bodyFat"] = (f.quantity.doubleValue(for: .percent()) * 1000).rounded() / 10; used.insert(f.uuid) }
            if let l = near(leans, w.endDate) { v["leanMass"] = (l.quantity.doubleValue(for: kg) * 10).rounded() / 10 }
            out.append(("health-" + w.uuid.uuidString, Day.string(w.endDate), v))
        }
        for f in fats where !used.contains(f.uuid) {
            out.append(("health-" + f.uuid.uuidString, Day.string(f.endDate), ["bodyFat": (f.quantity.doubleValue(for: .percent()) * 1000).rounded() / 10]))
        }
        return out
    }

    /// Durchschnittliche aktive Energie pro Tag (letzte 14 Tage), nil ohne Daten
    static func averageActiveEnergy() async -> Double? {
        let values = await daily(.activeEnergyBurned, .kilocalorie(), sum: true, days: 14).values.filter { $0 > 0 }
        return values.count >= 3 ? values.reduce(0, +) / Double(values.count) : nil
    }

    // MARK: Gemütszustand (State of Mind, ab iOS 18)

    /// Stimmung speichern: Stufe 1–7 → Valenz −1…1, dazu Gefühle und Lebensbereiche (Kennungen aus MoodModule)
    static func saveMood(level: Int, daily: Bool, feelings: [String], areas: [String]) {
        guard #available(iOS 18.0, *) else { return }
        let s = HKStateOfMind(date: Date(), kind: daily ? .dailyMood : .momentaryEmotion, valence: Mood.valence(level),
                              labels: feelings.compactMap { Mood.hkLabels[$0] }, associations: areas.compactMap { Mood.hkAreas[$0] })
        store.save(s) { _, _ in }
    }

    /// Stimmungen aus Health (andere Apps, Health-App, Watch); eigene werden übersprungen
    static func moods(days: Int) async -> [(id: String, date: String, values: [String: Any])] {
        guard #available(iOS 18.0, *) else { return [] }
        let p = HKQuery.predicateForSamples(withStart: since(days), end: nil)
        let samples = (try? await HKSampleQueryDescriptor(predicates: [.stateOfMind(p)], sortDescriptors: []).result(for: store)) ?? []
        return samples.filter { $0.sourceRevision.source != HKSource.default() }.map { s in
            let feelings = s.labels.compactMap { l in Mood.hkLabels.first { $0.value == l }?.key }
            let areas = s.associations.compactMap { a in Mood.hkAreas.first { $0.value == a }?.key }
            return ("health-" + s.uuid.uuidString, Day.string(s.startDate), [
                "mood": Mood.level(s.valence), "valence": s.valence, "feelings": feelings, "areas": areas,
                "kind": s.kind == .dailyMood ? "daily" : "moment", "time": s.startDate.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)),
            ])
        }
    }

    static func saveWeight(_ kg: Double) {
        let s = HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg), start: Date(), end: Date())
        store.save(s) { _, _ in }
    }

    /// Getränk nach Health: Wasser (ohne Alkoholisches), Koffein, alkoholische Getränke (≈ 10 g Alkohol je Getränk),
    /// Kalorien und Kohlenhydrate. Nur mit Health-Freigabe und nur für heute. Gibt den Eintrag unverändert zurück.
    @discardableResult
    static func logDrink(_ e: Entry) -> Entry {
        guard UserDefaults.standard.bool(forKey: "healthEnabled"), e.date == Day.today else { return e }
        let meta = [HKMetadataKeyFoodType: e.text("name") ?? "Getränk"]
        let values: [(HKQuantityTypeIdentifier, HKUnit, Double)] = [
            (.dietaryWater, .literUnit(with: .milli), e.num("hydration") ?? 0), (.dietaryCaffeine, .gramUnit(with: .milli), e.num("caffeine") ?? 0),
            (.numberOfAlcoholicBeverages, .count(), (e.num("alcohol") ?? 0) / 10),
            (.dietaryEnergyConsumed, .kilocalorie(), e.num("kcal") ?? 0), (.dietaryCarbohydrates, .gram(), e.num("carbs") ?? 0),
        ]
        let samples: [HKSample] = values.filter { $0.2 > 0 }.map {
            HKQuantitySample(type: HKQuantityType($0.0), quantity: HKQuantity(unit: $0.1, doubleValue: $0.2), start: Date(), end: Date(), metadata: meta)
        }
        if !samples.isEmpty { store.save(samples) { _, _ in } }
        return e
    }

    /// Training als Workout nach Health (endet jetzt, Dauer in Minuten); die Sportart wird grob aus dem Namen erkannt
    static func saveWorkout(name: String, minutes: Double) {
        guard UserDefaults.standard.bool(forKey: "healthEnabled"), minutes > 0 else { return }
        let n = name.lowercased()
        let kinds: [(String, HKWorkoutActivityType)] = [("lauf", .running), ("jogg", .running), ("rad", .cycling), ("bike", .cycling),
            ("spazier", .walking), ("geh", .walking), ("wander", .hiking), ("schwimm", .swimming), ("yoga", .yoga), ("hiit", .highIntensityIntervalTraining)]
        let config = HKWorkoutConfiguration()
        config.activityType = kinds.first { n.contains($0.0) }?.1 ?? .traditionalStrengthTraining
        let end = Date(), builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        builder.beginCollection(withStart: end.addingTimeInterval(-minutes * 60)) { ok, _ in
            guard ok else { return }
            builder.addMetadata([HKMetadataKeyWorkoutBrandName: name]) { _, _ in
                builder.endCollection(withEnd: end) { _, _ in builder.finishWorkout { _, _ in } }
            }
        }
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
