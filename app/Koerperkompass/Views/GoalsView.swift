import Charts
import SwiftUI

/// „Mein Plan“: Überblick über Ziel, BMI, Tagesziele und Training – alles aus dem Profil berechnet.
struct GoalsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context

    var body: some View {
        let p = state.profile
        let weight = context.allEntries().last { $0.module == "body" && !$0.deleted && $0.num("weight") != nil }?.num("weight") ?? p.weight
        let path = projection(from: weight, to: p.targetWeight)
        let bmi = weight / pow(p.height / 100, 2)
        List {
            Section {
                Chart(path.indices, id: \.self) { i in
                    LineMark(x: .value("Datum", path[i].date), y: .value("kg", path[i].kg))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.linearGradient(colors: [.orange, .green], startPoint: .leading, endPoint: .trailing))
                        .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)
                HStack {
                    Text("\(weight.short) kg").bold()
                    Spacer()
                    Image(systemName: "arrow.right")
                    Spacer()
                    Text("\(p.targetWeight.short) kg").bold().foregroundStyle(.green)
                }
                if let end = path.last?.date, path.count > 1 {
                    Text("Bei gesundem Tempo voraussichtlich erreicht: \(end.formatted(.dateTime.month(.wide).year()))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Ziel") }

            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text(bmi.short).font(.system(size: 44, weight: .bold))
                    Spacer()
                    Text(bmiCategory(bmi)).font(.headline).foregroundStyle(bmiColor(bmi))
                }
                BMIBar(bmi: bmi)
                Text("Der BMI ist nur ein grober Richtwert – Muskelmasse und Körperbau berücksichtigt er nicht.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("BMI") }

            Section("Tagesziele") {
                LabeledContent("Kalorien", value: "\(p.kcal.whole) kcal")
                LabeledContent("Eiweiß", value: "\(p.protein.whole) g")
                LabeledContent("Kohlenhydrate", value: "\(p.carbs.whole) g")
                LabeledContent("Fett", value: "\(p.fat.whole) g")
                LabeledContent("Wasser", value: "\((p.water ?? 2000).whole) ml (≈ \(((p.water ?? 2000) / 250).short) Gläser)")
            }

            Section("Training") {
                LabeledContent { Text(p.goal.title) } label: { Text("Ziel") }
                LabeledContent { Text(Profile.activityNames[min(max(p.activity, 0), 4)]) } label: { Text("Aktivität") }
                LabeledContent("Programm", value: p.plan?.name ?? "–")
                LabeledContent("Workouts pro Woche", value: p.plan.map { "\($0.weekdays.count)" } ?? "–")
            }

            Section {
                NavigationLink("Ziele anpassen") { SetupView(editing: true) }
            } footer: {
                Text("Alle Werte sind Schätzungen und ersetzen keine ärztliche oder ernährungsfachliche Beratung.")
            }
        }
        .navigationTitle("Mein Plan")
    }

    /// Gewichtsverlauf bei 0,5 kg pro Woche (Abnehmen) bzw. 0,25 kg pro Woche (Zunehmen)
    private func projection(from start: Double, to target: Double) -> [(date: Date, kg: Double)] {
        let rate = target < start ? 0.5 : 0.25
        let weeks = max(1, Int((abs(target - start) / rate).rounded(.up)))
        return (0...weeks).map { w -> (date: Date, kg: Double) in
            let t = Double(w) / Double(weeks)
            let eased = t * t * (3 - 2 * t)  // weicher Verlauf am Anfang und Ende
            return (Calendar.current.date(byAdding: .weekOfYear, value: w, to: Date())!, start + (target - start) * eased)
        }
    }
}

func bmiCategory(_ bmi: Double) -> LocalizedStringResource {
    bmi < 18.5 ? "Untergewicht" : bmi < 25 ? "Normalgewicht" : bmi < 30 ? "Übergewicht" : "Adipositas"
}

func bmiColor(_ bmi: Double) -> Color {
    bmi < 18.5 ? .blue : bmi < 25 ? .green : bmi < 30 ? .yellow : .red
}

/// Farbskala 15–35 mit Markierung
private struct BMIBar: View {
    let bmi: Double
    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { g in
                let x = min(max((bmi - 15) / 20, 0), 1) * g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.linearGradient(stops: [
                        .init(color: .blue, location: 0), .init(color: .green, location: 0.2), .init(color: .green, location: 0.45),
                        .init(color: .yellow, location: 0.55), .init(color: .yellow, location: 0.7), .init(color: .red, location: 1),
                    ], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 10)
                    Capsule().fill(.white).frame(width: 6, height: 22).shadow(radius: 2).offset(x: x - 3)
                }
            }
            .frame(height: 22)
            HStack {
                Text("Unter").frame(maxWidth: .infinity, alignment: .leading)
                Text("Normal").frame(maxWidth: .infinity)
                Text("Über").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
