import SwiftUI
import Charts

struct BodyActivityHealthScreen: View {
    @Environment(DataStore.self) private var data
    @Environment(\.scenePhase) private var phase
    private var state: BodyActivityHealthState { data.settings.bodyActivityHealth ?? .init() }
    var body: some View {
        List {
            BodyHealthConnectionSection()
            if state.enabled {
                Section {
                    measurement("Body weight", sample: state.snapshot?.latestWeight, weight: true)
                    measurement("Height", sample: state.snapshot?.latestHeight, weight: false)
                } header: { Text("Body measurements") } footer: { Text("Updates your profile and local nutrition targets. Manual targets stay fixed.") }
                if let values = state.snapshot?.weights, values.count > 1 {
                    Section("Weight trend") {
                        Chart(Array(values.suffix(30))) { item in
                            LineMark(x: .value("Date", item.date), y: .value("Body weight", data.settings.weightUnit.fromKg(item.value)))
                                .foregroundStyle(MasoColor.accent)
                        }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 140)
                    }
                }
                Section {
                    let today = state.snapshot?.today(calendar: data.settings.calendar)
                    healthValue("Steps", value: today?.steps, unit: "")
                    healthValue("Active energy", value: today?.activeEnergy, unit: "kcal")
                    healthValue("Resting energy", value: today?.restingEnergy, unit: "kcal")
                    healthValue("Energy burned", value: today?.totalEnergy, unit: "kcal")
                } header: { Text("Today so far") } footer: { Text("Recorded energy, not a full-day forecast. Your food target stays unchanged.") }
                Section {
                    NavigationLink("Health history") { BodyActivityHealthHistoryScreen() }
                        .accessibilityIdentifier("health.body.history")
                    if state.snapshot?.incomplete == true { Text("Some data couldn't refresh.").font(.footnote).foregroundStyle(.secondary) }
                    if state.snapshot?.weights.isEmpty != false && state.snapshot?.heights.isEmpty != false && state.snapshot?.activity.isEmpty != false {
                        Text("No records yet. Check access and data in Apple Health.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section { Text("Imported health data stays on this device and is not sent to AI Coach.").font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("Apple Health").navigationBarTitleDisplayMode(.inline)
        .task { await data.refreshBodyActivityHealth() }
        .onChange(of: phase) { _, phase in if phase == .active { Task { await data.refreshBodyActivityHealth() } } }
    }
    private func measurement(_ title: LocalizedStringKey, sample: BodyHealthMeasurement?, weight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            healthValue(title, value: sample.map { weight ? data.settings.weightUnit.fromKg($0.value) : $0.value },
                        unit: weight ? data.settings.weightUnit.label : "cm", decimals: true)
            if let sample {
                Text(verbatim: sample.source + " · " + sample.date.formatted(.dateTime.year().month().day().locale(LanguageManager.currentLocale)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func healthValue(_ title: LocalizedStringKey, value: Double?, unit: String, decimals: Bool = false) -> some View {
        LabeledContent(title, value: healthNumber(value, decimals: decimals) + (value == nil || unit.isEmpty ? "" : " " + unit))
    }
}

func healthNumber(_ value: Double?, decimals: Bool = false) -> String {
    guard let value, value.isFinite, value >= 0 else { return "—" }
    return value.formatted(.number.precision(.fractionLength(decimals ? 0...1 : 0...0)).locale(LanguageManager.currentLocale))
}

struct BodyActivityHealthHistoryScreen: View {
    @Environment(DataStore.self) private var data
    @State private var kind = 0
    var body: some View {
        List {
            Picker("Content", selection: $kind) { Text("Body weight").tag(0); Text("Height").tag(1); Text("Activity").tag(2) }
            if let snapshot = data.settings.bodyActivityHealth?.snapshot {
                if kind == 2 {
                    ForEach(snapshot.activity.reversed()) { item in
                        Section(item.day.formatted(.dateTime.year().month().day().locale(LanguageManager.currentLocale))) {
                            LabeledContent("Steps", value: healthNumber(item.steps))
                            LabeledContent("Active energy", value: healthNumber(item.activeEnergy) + " kcal")
                            LabeledContent("Resting energy", value: healthNumber(item.restingEnergy) + " kcal")
                        }
                    }
                } else {
                    let values = kind == 0 ? snapshot.weights : snapshot.heights
                    ForEach(values.reversed()) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent {
                                Text(verbatim: healthNumber(kind == 0 ? data.settings.weightUnit.fromKg(item.value) : item.value, decimals: true) + (kind == 0 ? " " + data.settings.weightUnit.label : " cm"))
                            } label: { Text(item.date, format: .dateTime.year().month().day().hour().minute()) }
                            Text(verbatim: item.source).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.navigationTitle("Health history").navigationBarTitleDisplayMode(.inline)
    }
}

/// Shared explicit authorization entry; never asks for permission on page appearance.
struct BodyHealthConnectionSection: View {
    @Environment(DataStore.self) private var data
    @State private var connecting = false
    @State private var failed = false
    private var state: BodyActivityHealthState { data.settings.bodyActivityHealth ?? .init() }
    var body: some View {
            Section {
                Toggle("Apple Health", isOn: Binding(get: { state.enabled }, set: connect))
                    .toggleStyle(.switch).tint(MasoColor.toggleAccent).disabled(connecting || !HealthKitService.isAvailable)
                    .accessibilityIdentifier("health.body.enabled")
                if state.enabled {
                    Button { Task { await data.refreshBodyActivityHealth() } } label: {
                        HStack { Text("Refresh"); Spacer(); if data.refreshingBodyActivityHealth || connecting { ProgressView() } }
                    }.disabled(connecting || data.refreshingBodyActivityHealth)
                    if let date = state.snapshot?.refreshedAt {
                        LabeledContent("Last synced", value: date.formatted(.dateTime.month().day().hour().minute().locale(LanguageManager.currentLocale)))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Read available history for weight, height, steps and energy.")
            }
        .alert("Couldn't read Apple Health. Try again.", isPresented: $failed) { Button("OK", role: .cancel) {} }
    }
    private func connect(_ enabled: Bool) {
        var next = state; next.enabled = enabled
        if !enabled { next.snapshot = nil }
        data.settings.bodyActivityHealth = next; data.save()
        guard enabled else { return }
        connecting = true
        Task {
            defer { connecting = false }
            do {
#if DEBUG
                if ProcessInfo.processInfo.environment["MASO_HEALTH_BODY_FIXTURE"] != "1" {
                    try await HealthKitService.shared.connectBodyActivity()
                }
#else
                try await HealthKitService.shared.connectBodyActivity()
#endif
                await data.refreshBodyActivityHealth()
            } catch { failed = true }
        }
    }
}

/// One place for Health-backed measurements and optional manual entry.
struct BodyProfileScreen: View {
    @Environment(DataStore.self) private var data
    @State private var editing: Measurement?
    enum Measurement: String, Identifiable {
        case weight, height
        var id: String { rawValue }
        var title: LocalizedStringKey { self == .weight ? "Body weight" : "Height" }
    }
    var body: some View {
        List {
            BodyHealthConnectionSection()
            Section("Body measurements") {
                measurement(.weight)
                measurement(.height)
            }
            if data.settings.bodyActivityHealth?.enabled == true {
                Section {
                    NavigationLink("Apple Health") { BodyActivityHealthScreen() }
                        .accessibilityIdentifier("profile.health.details")
                }
            }
        }
        .navigationTitle("Body measurements").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { field in BodyMeasurementEditor(field: field) }
        .task { await data.refreshBodyActivityHealth() }
    }
    private func measurement(_ field: Measurement) -> some View {
        let isWeight = field == .weight
        let state = data.settings.bodyActivityHealth
        let followed = isWeight ? state?.useWeight == true : state?.useHeight == true
        let applied = isWeight ? state?.appliedWeight : state?.appliedHeight
        let value = isWeight ? data.settings.weight.map { data.settings.weightUnit.fromKg($0) } : data.settings.heightCentimeters
        let sample = isWeight ? state?.snapshot?.latestWeight : state?.snapshot?.latestHeight
        let validSample = sample.map { (isWeight ? 20...500 : 50...260).contains($0.value) } ?? false
        return VStack(alignment: .leading, spacing: 6) {
            Button { editing = field } label: {
                LabeledContent {
                    HStack(spacing: 8) {
                        Text(verbatim: healthNumber(value, decimals: true) + (value == nil ? "" : " " + (isWeight ? data.settings.weightUnit.label : "cm")))
                            .foregroundStyle(MasoColor.text)
                        Image(systemName: "pencil").foregroundStyle(MasoColor.textDim)
                    }
                } label: { Text(field.title).foregroundStyle(MasoColor.text) }
            }.accessibilityIdentifier("profile.body." + field.rawValue)
            if applied != nil {
                HStack(spacing: 4) {
                    Text("Apple Health")
                    if let sample { Text(sample.date, format: .dateTime.year().month().day()) }
                }.font(.caption).foregroundStyle(.secondary)
            }
            if state?.enabled == true, followed || validSample {
                Toggle(LocalizedStringKey(isWeight ? "Use Health weight" : "Use Health height"), isOn: Binding(
                    get: { isWeight ? data.settings.bodyActivityHealth?.useWeight == true : data.settings.bodyActivityHealth?.useHeight == true },
                    set: { enabled in
                        if isWeight { data.settings.bodyActivityHealth?.useWeight = enabled }
                        else { data.settings.bodyActivityHealth?.useHeight = enabled }
                        if let snapshot = data.settings.bodyActivityHealth?.snapshot { data.settings.applyBodyActivityHealth(snapshot) }
                        data.captureWellnessGoal(updateDiet: true); data.save()
                    }))
                    .font(.subheadline).toggleStyle(.switch).tint(MasoColor.toggleAccent)
                    .accessibilityIdentifier("profile.body.follow-" + field.rawValue)
            }
        }
    }
}

private struct BodyMeasurementEditor: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    let field: BodyProfileScreen.Measurement
    @State private var text = ""
    private var value: Double? {
        guard let raw = NumericInputRules.value(text, allowsDecimal: true, locale: LanguageManager.currentLocale) else { return nil }
        let canonical = field == .weight ? data.settings.weightUnit.toKg(raw) : raw
        return (field == .weight ? 20...500 : 50...260).contains(canonical) ? canonical : nil
    }
    var body: some View {
        AppNavigationStack {
            Form {
                HStack {
                    NumericTextField(text: $text, allowsDecimal: true,
                        placeholder: NSLocalizedString(field == .weight ? "Body weight" : "Height", comment: ""),
                        textAlignment: .natural,
                        accessibilityLabel: NSLocalizedString(field == .weight ? "Body weight" : "Height", comment: ""))
                        .accessibilityIdentifier("profile.body.input")
                    Text(field == .weight ? data.settings.weightUnit.label : "cm").foregroundStyle(.secondary)
                }
            }
            .navigationTitle(field.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let value else { return }
                        data.settings.setManualBodyMeasurement(value, weight: field == .weight)
                        data.captureWellnessGoal(updateDiet: true); data.save(); dismiss()
                    }.disabled(value == nil).accessibilityIdentifier("profile.body.save")
                }
            }
            .onAppear {
                let stored = field == .weight ? data.settings.weight.map { data.settings.weightUnit.fromKg($0) } : data.settings.heightCentimeters
                text = stored.map { NumericInputRules.formatted($0, allowsDecimal: true, locale: LanguageManager.currentLocale) } ?? ""
            }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}
