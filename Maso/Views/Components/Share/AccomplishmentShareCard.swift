import SwiftUI
import UIKit

/// Preview and the exported bitmap both draw this view from the same model.
struct AccomplishmentCard: View {
    enum Model: Equatable {
        case rhythm(AccomplishmentShare.Rhythm)
        case session(AccomplishmentShare.SessionFact, AccomplishmentShare.SessionPresentation)
        case progress(AccomplishmentShare.Progress, unit: WeightUnit)
    }
    let model: Model
    var photo: UIImage? = nil
    private var locale: Locale { LanguageManager.currentLocale }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                switch model {
                case .rhythm(let rhythm): rhythmBody(rhythm)
                case .session(let fact, let presentation): sessionBody(fact, presentation)
                case .progress(let progress, let unit): progressBody(progress, unit)
                }
            }.padding(ShareLayout.contentInset)
            ShareCardFooter(qrPayload: MasoLinks.appStore)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MasoColor.background)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, locale)
        .environment(\.layoutDirection, LanguageManager.currentLanguageCode == "ar" ? .rightToLeft : .leftToRight)
    }

    private func rhythmBody(_ rhythm: AccomplishmentShare.Rhythm) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedStringKey(rhythm.monthly ? "This month" : "This week"))
                .font(.largeTitle.bold())
                .foregroundStyle(MasoColor.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(rhythmSubtitle(rhythm))
                .font(.subheadline)
                .foregroundStyle(MasoColor.textDim)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                rhythmMetric("Workout", detail: "Training days", value: rhythm.trainingDays.formatted(.number.locale(locale)), color: MasoColor.accent)
                Divider()
                rhythmMetric("Diet", detail: "Average target progress", value: rhythm.averageDiet.map { Int(($0 * 100).rounded()).formatted(.number.locale(locale)) + "%" } ?? "—", color: MasoColor.dietAccent)
                Divider()
                rhythmMetric("Sleep", detail: "Average sleep", value: rhythm.averageSleep.map(compactSleepDuration) ?? "—", color: MasoColor.sleepAccent)
            }.contentCardChrome(padding: 16)
            VStack(alignment: .leading, spacing: 12) {
                monthGrid(rhythm)
                HStack(spacing: 12) {
                    rhythmLegend("Workout", color: MasoColor.accent)
                    rhythmLegend("Diet", color: MasoColor.dietAccent)
                    rhythmLegend("Sleep", color: MasoColor.sleepAccent)
                }
            }.contentCardChrome(padding: 16)
        }
    }

    private func rhythmLegend(_ title: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 6, height: 6); Text(title).font(.caption2).foregroundStyle(MasoColor.textDim) }
    }

    private func rhythmMetric(_ title: LocalizedStringKey, detail: LocalizedStringKey, value: String, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(color)
                Text(detail).font(.caption).foregroundStyle(MasoColor.textDim)
            }
            Spacer(minLength: 8)
            Text(value).font(.title3.weight(.bold)).foregroundStyle(MasoColor.text).multilineTextAlignment(.trailing)
        }.padding(.vertical, 9).accessibilityElement(children: .combine)
    }

    private func sessionBody(_ fact: AccomplishmentShare.SessionFact, _ presentation: AccomplishmentShare.SessionPresentation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if presentation.includesPhoto, let photo {
                Image(uiImage: photo)
                    .resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 160)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("Workout photo")
            }
            Text(LocalizedStringKey(fact.isAggregate ? "This day's records" : "Just finished"))
                .font(.headline)
                .foregroundStyle(MasoColor.text)
            Text(fact.name.isEmpty ? NSLocalizedString("Free workout", comment: "") : fact.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(MasoColor.accent)
                .fixedSize(horizontal: false, vertical: true)
            Text(sessionDateLine(fact, presentation))
                .font(.subheadline)
                .foregroundStyle(MasoColor.textDim)
                .fixedSize(horizontal: false, vertical: true)
            if fact.setCount > 0 {
                HStack(spacing: 12) {
                    if let minutes = fact.durationMinutes {
                        statTile(value: minutes, label: "Minutes", accent: true)
                    }
                    statTile(value: fact.setCount, label: "Sets", accent: false)
                }
            } else {
                Text("No completed sets to share")
                    .font(.subheadline)
                    .foregroundStyle(MasoColor.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func progressBody(_ progress: AccomplishmentShare.Progress, _ unit: WeightUnit) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Same exercise, another step")
                .font(.headline)
                .foregroundStyle(MasoColor.text)
            Text(progress.name)
                .font(.title3.weight(.bold))
                .foregroundStyle(MasoColor.accent)
                .fixedSize(horizontal: false, vertical: true)
            Text(progressCaption(progress))
                .font(.subheadline)
                .foregroundStyle(MasoColor.textDim)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Text(progress.previousDate.formatted(.dateTime.year().month(.abbreviated).day().locale(locale)))
                    .font(.subheadline).foregroundStyle(MasoColor.textDim)
                Text(load(progress.previousKg, unit: unit, reps: progress.reps))
                    .font(.title2.weight(.bold)).foregroundStyle(MasoColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(progress.currentDate.formatted(.dateTime.year().month(.abbreviated).day().locale(locale))
                     + " · " + load(progress.currentKg, unit: unit, reps: progress.reps))
                    .font(.subheadline).foregroundStyle(MasoColor.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MasoColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(deltaLine(progress, unit: unit))
                .font(.headline)
                .foregroundStyle(MasoColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statTile(value: Int, label: LocalizedStringKey, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.formatted(.number.locale(locale)))
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(accent ? MasoColor.accent : MasoColor.text)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(MasoColor.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(MasoColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func monthGrid(_ rhythm: AccomplishmentShare.Rhythm) -> some View {
        let symbols = weekdaySymbols(matching: rhythm)
        let leading = leadingBlanks(rhythm)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(symbols.indices, id: \.self) { index in
                    Text(symbols[index])
                        .font(.caption2)
                        .foregroundStyle(MasoColor.textDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 16)
                        .accessibilityHidden(true)
                }
                ForEach(0..<leading, id: \.self) { _ in
                    Color.clear.frame(height: 28).accessibilityHidden(true)
                }
                ForEach(rhythm.days, id: \.date) { day in
                    dayCell(day, rhythm: rhythm)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func dayCell(_ day: AccomplishmentShare.Rhythm.Day, rhythm: AccomplishmentShare.Rhythm) -> some View {
        let calendar = gridCalendar(rhythm)
        return ZStack {
            DailyProgressRing(progress: [day.sessions > 0 ? 1 : nil, day.dietProgress, day.sleepProgress],
                colors: [MasoColor.accent, MasoColor.dietAccent, MasoColor.sleepAccent], lineWidth: 3,
                dietCalorieFraction: day.dietProgress)
            Text(calendar.component(.day, from: day.date).formatted(.number.locale(locale)))
                .font(.caption).monospacedDigit()
                .foregroundStyle(day.isFuture ? MasoColor.textFaint : MasoColor.text)
        }.frame(height: 36)

        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayAccessibility(day))
    }

    private func rhythmTitle(_ rhythm: AccomplishmentShare.Rhythm) -> String {
        if rhythm.isEmpty { return NSLocalizedString("No workouts logged", comment: "empty share rhythm") }
        let key = rhythm.monthly ? "This month, %d training days" : "This week, %d training days"
        return String(format: NSLocalizedString(key, comment: "share rhythm title"), locale: locale, rhythm.trainingDays)
    }

    private func rhythmSubtitle(_ rhythm: AccomplishmentShare.Rhythm) -> String {
        let start = rhythm.start.formatted(.dateTime.year().month(.abbreviated).day().locale(locale))
        let end = rhythm.end.formatted(.dateTime.month(.abbreviated).day().locale(locale))
        let range = start + " – " + end
        guard let asOf = rhythm.asOf else { return range }
        let day = asOf.formatted(.dateTime.month(.abbreviated).day().locale(locale))
        return range + " · " + String(format: NSLocalizedString("As of %@", comment: "unfinished share range"), locale: locale, day)
    }

    private func sessionDateLine(_ fact: AccomplishmentShare.SessionFact, _ presentation: AccomplishmentShare.SessionPresentation) -> String {
        let day = fact.start.formatted(.dateTime.year().month(.abbreviated).day().locale(locale))
        if presentation.showsExactTime {
            let time = fact.start.formatted(.dateTime.hour().minute().locale(locale))
            return day + " · " + time
        }
        if presentation.showsDayPart, let part = fact.dayPart {
            return day + " · " + NSLocalizedString(part.titleKey, comment: "coarse time of day")
        }
        return day
    }

    private func progressCaption(_ progress: AccomplishmentShare.Progress) -> String {
        let reps = String(format: NSLocalizedString("%d reps", comment: "insights reps"), locale: locale, progress.reps)
        if progress.perDumbbell {
            return NSLocalizedString("per dumbbell", comment: "dumbbell load is one bell") + " · " + reps
        }
        return reps
    }

    private func load(_ kg: Double, unit: WeightUnit, reps: Int) -> String {
        let number = unit.fromKg(kg).formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return "\(number) \(unit.label) × \(reps)"
    }

    private func deltaLine(_ progress: AccomplishmentShare.Progress, unit: WeightUnit) -> String {
        let number = unit.fromKg(progress.deltaKg).formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        let signed = "+\(number) \(unit.label)"
        return String(format: NSLocalizedString("%@ · same reps", comment: "progress delta at the same rep count"), locale: locale, signed)
    }

    private func gridCalendar(_ rhythm: AccomplishmentShare.Rhythm) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.firstWeekday = rhythm.firstWeekday
        if let zone = TimeZone(identifier: rhythm.timeZoneID) { calendar.timeZone = zone }
        return calendar
    }

    private func weekdaySymbols(matching rhythm: AccomplishmentShare.Rhythm) -> [String] {
        let calendar = gridCalendar(rhythm)
        let symbols = calendar.veryShortWeekdaySymbols
        let first = max(0, calendar.firstWeekday - 1)
        guard symbols.count == 7 else { return symbols }
        return (0..<7).map { symbols[($0 + first) % 7] }
    }

    private func leadingBlanks(_ rhythm: AccomplishmentShare.Rhythm) -> Int {
        guard rhythm.monthly, let first = rhythm.days.first else { return 0 }
        let calendar = gridCalendar(rhythm)
        let weekday = calendar.component(.weekday, from: first.date)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private func dayAccessibility(_ day: AccomplishmentShare.Rhythm.Day) -> String {
        let date = day.date.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(locale))
        if day.isFuture { return date + ", " + NSLocalizedString("Future day", comment: "share calendar future day") }
        let count = day.sessions == 0 ? NSLocalizedString("No workout logged", comment: "share calendar empty day") : String(format: NSLocalizedString("%d sessions", comment: "share session count"), locale: locale, day.sessions)
        let missing = NSLocalizedString("No data", comment: "")
        let diet = day.dietProgress.map { Int(($0 * 100).rounded()).formatted(.number.locale(locale)) + "%" } ?? missing
        let sleep = day.sleepMinutes.map(compactSleepDuration) ?? missing
        return date + ", " + count + ", " + NSLocalizedString("Diet", comment: "") + ": " + diet + ", " + NSLocalizedString("Sleep", comment: "") + ": " + sleep
    }
}

extension AccomplishmentShare.DayPart {
    var titleKey: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        case .night: return "Night"
        }
    }
}

/// Privacy toggles stay outside the card. The bitmap is the same view as the preview.
struct AccomplishmentShareSheet: View {
    let title: LocalizedStringKey
    let model: (AccomplishmentShare.Privacy) -> AccomplishmentCard.Model
    var allowsExactTime = false
    var allowsPhoto = true
    var canShare = true
    var rhythmModels: [AccomplishmentCard.Model] = []
    var initialMonthly = false
    @State private var monthly: Bool? = nil
    private var selectedModel: AccomplishmentCard.Model {
        rhythmModels.count == 2 ? rhythmModels[(monthly ?? initialMonthly) ? 1 : 0] : model(privacy)
    }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var privacy = AccomplishmentShare.Privacy()
    @State private var photo: UIImage?
    @State private var picker: PhotoPickerSource?
    @State private var rendered: UIImage?
    @State private var showPhotoOptions = false

    var body: some View {
        let card = AccomplishmentCard(model: selectedModel, photo: privacy.includePhoto ? photo : nil)
        AppNavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if rhythmModels.count == 2 {
                        Picker("Period", selection: Binding(get: { monthly ?? initialMonthly }, set: { monthly = $0 })) {
                            Text("Week").tag(false)
                            Text("Month").tag(true)
                        }.pickerStyle(.segmented).padding(.horizontal, ShareLayout.contentInset).accessibilityIdentifier("calendar.share.period")
                    }
                    card.frame(maxWidth: .infinity)
                    if allowsExactTime {
                        Toggle("Exact time", isOn: $privacy.includeExactTime)
                            .tint(MasoColor.accent)
                            .accessibilityIdentifier("share.privacy.exact-time")
                    }
                    if allowsPhoto {
                    Button {
                        showPhotoOptions = true
                    } label: {
                        Label {
                            if privacy.includePhoto && photo != nil {
                                Text("Photo included")
                            } else {
                                Text("Add photo")
                            }
                        } icon: {
                            Image(systemName: "photo")
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("share.privacy.photo")
                    }
                    if rhythmModels.isEmpty {
                        Text("Heart rate, body weight, location, and your name stay off this card.")
                            .font(.footnote).foregroundStyle(MasoColor.textDim)
                            .padding(.horizontal, ShareLayout.contentInset)
                    }
                }
                .padding(.top, 16)
            }
            .background(MasoColor.background)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("share.privacy.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") { export() }
                        .disabled(!canShare)
                        .accessibilityIdentifier("share.privacy.export")
                }
            }
            .confirmationDialog("Photo", isPresented: $showPhotoOptions, titleVisibility: .visible) {
                Button("Choose from Library") { picker = .photoLibrary }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") { picker = .camera }
                }
                if photo != nil {
                    Button("Remove Photo", role: .destructive) {
                        photo = nil
                        privacy.includePhoto = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $picker) { source in
                PhotoPicker(image: $photo, source: source)
            }
            .onChange(of: photo) { _, newPhoto in
                privacy.includePhoto = newPhoto != nil
            }
            .sheet(isPresented: Binding(get: { rendered != nil }, set: { if !$0 { rendered = nil } })) {
                if let rendered {
                    ActivityViewController(activityItems: [rendered]) { completed in
                        self.rendered = nil
                        if completed { dismiss() }
                    }
                }
            }
        }
        .tint(MasoColor.text)
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .presentationBackground(MasoColor.background)
    }

    private func export() {
        let snapshot = AccomplishmentCard(model: selectedModel, photo: privacy.includePhoto ? photo : nil)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, LanguageManager.currentLocale)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
        guard let image = ShareImageRenderer.render(width: 390, { snapshot }) else { return }
        if let data = image.pngData(), let normalized = UIImage(data: data) {
            rendered = normalized
        } else {
            rendered = image
        }
    }
}
