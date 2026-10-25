import SwiftUI

/// Main screen: pick your state, turn on reminders, tap "I voted".
/// The drag-up voting plan sheet (PlanSheet) sits along the bottom until you vote.
struct ContentView: View {
    @EnvironmentObject private var model: VotingModel
    @AppStorage(ReminderScheduler.hasVotedKey) private var hasVoted = false
    @AppStorage(ReminderScheduler.remindersKey) private var remindersOn = false
    @State private var planDetent: PresentationDetent = PlanSheet.collapsed

    private var sortedStates: [(code: String, name: String)] {
        Midterms2026.byCode.map { ($0.key, $0.value.name) }.sorted { $0.name < $1.name }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                statePicker
                if let rules = model.stateRules { dates(for: rules) }
                if let error = model.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                reminders
                VStack(alignment: .leading, spacing: 10) {
                    Link("Check your registration and polling place at vote.gov",
                         destination: URL(string: "https://vote.gov")!)
                    Link("Click here if you plan to vote by mail",
                         destination: URL(string: "https://www.usa.gov/absentee-voting")!)
                }
                .font(.footnote)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        // Leave room so the pulled-down plan sheet doesn't cover the bottom of the screen.
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: hasVoted ? 0 : 96) }
        .sheet(isPresented: Binding(get: { !hasVoted }, set: { _ in })) {
            PlanSheet(detent: $planDetent)
                .environmentObject(model)
                .presentationDetents([PlanSheet.collapsed, .medium, .large], selection: $planDetent)
                .presentationBackgroundInteraction(.enabled(upThrough: PlanSheet.collapsed))
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Wordmark()
                .padding(.bottom, 14)
            Text("Election Day is\nTuesday, November 3")
                .font(.system(.largeTitle, design: .rounded).weight(.black))
                .foregroundStyle(Brand.ink)
            if let days = daysUntil(Midterms2026.electionDay), days >= 0 {
                Text(days == 0 ? "That's today." : "\(days) day\(days == 1 ? "" : "s") away.")
                    .font(.title3).foregroundStyle(.secondary)
            }
        }
    }

    private var statePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("State where you're registered to vote")
                .font(.subheadline.weight(.semibold))
            HStack {
                Menu {
                    ForEach(sortedStates, id: \.code) { state in
                        Button(state.name) { Task { await model.selectState(state.code) } }
                    }
                } label: {
                    HStack {
                        Text(model.stateRules?.name ?? "Choose your state")
                            .foregroundStyle(model.stateRules == nil ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .tint(.primary)

                Button {
                    Task { await model.detectState() }
                } label: {
                    if model.isLoading { ProgressView() } else { Image(systemName: "location.fill") }
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Use my current location")
            }
        }
    }

    private func dates(for rules: StateVotingRules) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Early voting", value: earlyText(rules))
            row("Election Day polls", value: "\(clock(rules.pollsOpen)) – \(clock(rules.pollsClose))")
            if rules.allMail {
                Text("\(rules.name) mails a ballot to every active voter. You can return it or vote in person.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let note = rules.note {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }

    private var reminders: some View {
        VStack(alignment: .leading, spacing: 16) {
            if hasVoted {
                VotedBadge(stickerSize: 128) { hasVoted = false }
            } else {
                Toggle(isOn: Binding(
                    get: { remindersOn },
                    set: { on in
                        remindersOn = on
                        Task { await setReminders(on) }
                    })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remind me to vote").font(.headline)
                        Text(model.stateRules == nil
                             ? "Choose your state first"
                             : "Daily during early voting, hourly on Election Day")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(Brand.ink)
                .disabled(model.stateRules == nil)

                IVotedButton {
                    ReminderScheduler.markVoted()
                    hasVoted = true
                    remindersOn = false
                }
                .sensoryFeedback(.success, trigger: hasVoted)
            }
        }
    }

    // MARK: Helpers

    private func setReminders(_ on: Bool) async {
        if on {
            remindersOn = await model.enableReminders()
        } else {
            model.disableReminders()
            remindersOn = false
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).multilineTextAlignment(.trailing)
        }
    }

    private func earlyText(_ rules: StateVotingRules) -> String {
        guard let s = rules.earlyStart, let e = rules.earlyEnd else { return "Excuse required" }
        return "\(shortDate(s)) – \(shortDate(e))"
    }

    private func shortDate(_ ymd: String) -> String {
        VotingModel.dayFormatter.date(from: ymd)?.formatted(.dateTime.month(.abbreviated).day()) ?? ymd
    }

    private func clock(_ minutes: Int) -> String {
        Calendar.current.startOfDay(for: Date())
            .addingTimeInterval(TimeInterval(minutes * 60))
            .formatted(date: .omitted, time: .shortened)
    }

    private func daysUntil(_ ymd: String) -> Int? {
        guard let d = VotingModel.dayFormatter.date(from: ymd) else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: d).day
    }
}
