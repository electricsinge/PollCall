import SwiftUI

/// The drag-up sheet: pick when and where you'll vote, save it,
/// add it to Calendar, and get reminders every hour that day.
struct PlanSheet: View {
    /// Height of the sheet when it's pulled down.
    static let collapsed = PresentationDetent.height(96)

    @Binding var detent: PresentationDetent
    @EnvironmentObject private var model: VotingModel

    @State private var date = Date()
    @State private var place: PlannedPlace?
    @State private var didLoad = false
    @State private var showPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showCalendarPrompt = false
    @State private var showCalendar = false

    private let cal = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if let rules = model.stateRules, let range = dateRange {
                        whenSection(range)
                        whereSection
                        if let problem = dayProblem(rules) {
                            warning(problem)
                        } else if let note = placeNote {
                            warning(note)
                        }
                        if let errorMessage {
                            Text(errorMessage).font(.footnote).foregroundStyle(.red)
                        }
                        saveButton(blocked: dayProblem(rules) != nil)
                        if let saved = model.plan {
                            savedActions(saved)
                        }
                    } else if model.stateRules == nil {
                        Text("Choose your state on the main screen first, so Poll Call knows your voting dates.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("Voting for this election has ended.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showPicker) {
                PlacePicker(detent: $detent) { picked in place = picked }
            }
        }
        .onAppear(perform: loadPlan)
        .alert("Add your plan to Calendar?", isPresented: $showCalendarPrompt) {
            Button("Add to Calendar") { showCalendar = true }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Poll Call fills in the date, time and location, with directions in Maps.")
        }
        .sheet(isPresented: $showCalendar) {
            if let saved = model.plan {
                CalendarEventEditor(plan: saved) { showCalendar = false }
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: Sections

    /// Visible even when the sheet is pulled down.
    private var header: some View {
        Button {
            withAnimation { detent = .large }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .foregroundStyle(Brand.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your voting plan")
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(Brand.ink)
                    Text(summary)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if detent == Self.collapsed {
                    Image(systemName: "chevron.up").foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func whenSection(_ range: ClosedRange<Date>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("When you'll vote").font(.headline)
            DatePicker("When you'll vote", selection: $date, in: range,
                       displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(Brand.ink)
        }
    }

    private var whereSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where you'll vote").font(.headline)
            Button {
                showPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.title3)
                        .foregroundStyle(Brand.ink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place?.name ?? "Choose a voting location")
                            .foregroundStyle(.primary)
                        Text(place?.address ?? "Find official locations or search the map")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func saveButton(blocked: Bool) -> some View {
        let current = VotingPlan(date: date, place: place)
        let isSaved = model.plan == current
        return Button {
            Task { await save(current) }
        } label: {
            HStack {
                if isSaving { ProgressView().tint(.white) }
                Text(isSaved ? "Plan saved" : (model.plan == nil ? "Save my plan" : "Update my plan"))
                    .font(.system(.headline, design: .rounded).weight(.heavy))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(Brand.ink)
        .clipShape(Capsule())
        .disabled(blocked || isSaved || isSaving)
    }

    private func savedActions(_ saved: VotingPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On \(saved.date.formatted(.dateTime.weekday(.wide).month().day())), Poll Call reminds you every hour until you tap I voted.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button {
                    showCalendar = true
                } label: {
                    Label("Add to Calendar", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)
                .tint(Brand.ink)
                Spacer()
                Button("Clear plan", role: .destructive) {
                    Task {
                        await model.clearPlan()
                        place = nil
                    }
                }
                .font(.footnote)
            }
        }
    }

    // MARK: Logic

    private var summary: String {
        guard let plan = model.plan else { return "Not set yet. Swipe up to make one." }
        var text = plan.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        if let name = plan.place?.name { text += " · \(name)" }
        return text
    }

    private func loadPlan() {
        guard !didLoad else { return }
        didLoad = true
        if let saved = model.plan {
            date = saved.date
            place = saved.place
        } else if let range = dateRange {
            // Start the picker on Election Day at noon, or the closest allowed time.
            var start = range.lowerBound
            if let eday = model.electionDate,
               let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: eday) {
                start = noon
            }
            date = min(max(start, range.lowerBound), range.upperBound)
        }
    }

    private func save(_ plan: VotingPlan) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        if await model.savePlan(plan) {
            showCalendarPrompt = true
        } else {
            errorMessage = model.errorMessage ?? "Couldn't save your plan. Check that notifications are on in Settings."
        }
    }

    private var earlyStart: Date? { model.stateRules?.earlyStart.flatMap(VotingModel.dayFormatter.date(from:)) }
    private var earlyEnd: Date? { model.stateRules?.earlyEnd.flatMap(VotingModel.dayFormatter.date(from:)) }

    /// From now (or the first day of early voting) through poll closing on Election Day.
    private var dateRange: ClosedRange<Date>? {
        guard let rules = model.stateRules, let eday = model.electionDate else { return nil }
        let day0 = cal.startOfDay(for: eday)
        let upper = day0.addingTimeInterval(TimeInterval(rules.pollsClose * 60))
        let earliest = earlyStart ?? day0.addingTimeInterval(TimeInterval(rules.pollsOpen * 60))
        let lower = max(earliest, Date())
        guard lower < upper else { return nil }
        return lower...upper
    }

    private func isElectionDay(_ d: Date) -> Bool {
        guard let eday = model.electionDate else { return false }
        return cal.isDate(d, inSameDayAs: eday)
    }

    /// Why the chosen day or time doesn't work, if it doesn't.
    private func dayProblem(_ rules: StateVotingRules) -> String? {
        if isElectionDay(date) {
            let minute = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
            if minute < rules.pollsOpen || minute >= rules.pollsClose {
                return "Polls in \(rules.name) are open \(clock(rules.pollsOpen)) – \(clock(rules.pollsClose)) on Election Day. Pick a time in that window."
            }
            return nil
        }
        guard let s = earlyStart, let e = earlyEnd,
              let afterEarly = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: e)) else {
            return "\(rules.name) doesn't offer early in-person voting without an excuse. Pick Election Day instead."
        }
        if date < cal.startOfDay(for: s) || date >= afterEarly {
            return "Early voting in \(rules.name) runs \(shortDate(s)) – \(shortDate(e)). Pick a day in that window, or Election Day."
        }
        return nil
    }

    /// A heads-up about the chosen place for the chosen day.
    private var placeNote: String? {
        guard let place else { return nil }
        switch place.source {
        case .early where isElectionDay(date):
            return "Early voting sites are often closed on Election Day. Check this one is open, or choose your assigned polling place."
        case .electionDay where !isElectionDay(date):
            return "Election Day polling places are usually open only on Election Day. For early voting, choose an early voting site."
        default:
            return place.source.caution
        }
    }

    private func clock(_ minutes: Int) -> String {
        cal.startOfDay(for: Date()).addingTimeInterval(TimeInterval(minutes * 60))
            .formatted(date: .omitted, time: .shortened)
    }

    private func shortDate(_ d: Date) -> String {
        d.formatted(.dateTime.month(.abbreviated).day())
    }
}
