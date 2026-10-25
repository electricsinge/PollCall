import SwiftUI
import CoreLocation

enum SiteKind: String, CaseIterable {
    case electionDay = "Election Day polling places"
    case early = "Early voting sites"
    case dropOff = "Ballot drop-off"

    var symbol: String {
        switch self {
        case .electionDay: return "checkmark.rectangle.stack.fill"
        case .early: return "calendar"
        case .dropOff: return "tray.and.arrow.down.fill"
        }
    }
    var color: Color {
        switch self {
        case .electionDay: return Brand.ink
        case .early: return Brand.marigold
        case .dropOff: return Brand.slate
        }
    }
}

struct VotingSite: Identifiable, Hashable {
    let kind: SiteKind
    let name: String
    let address: String
    let hours: String?
    let notes: String?
    let startDate: String?
    let endDate: String?
    let coordinate: CLLocationCoordinate2D

    var id: String { "\(kind.rawValue)|\(address)" }
    static func == (a: VotingSite, b: VotingSite) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

@MainActor
final class VotingModel: ObservableObject {
    @Published var sites: [VotingSite] = []
    @Published var election: Election?
    @Published var address = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var notice: String?
    /// Two-letter state code for the looked-up address, e.g. "TX".
    @Published var stateCode: String?
    /// When and where the user plans to vote (the drag-up sheet).
    @Published var plan: VotingPlan? = VotingPlanStore.load()

    var stateRules: StateVotingRules? { Midterms2026.rules(for: stateCode) }

    private let location = LocationProvider()
    private static let savedStateKey = "stateCode"

    init() {
        // Restore the chosen state so the screen isn't blank after relaunch.
        if let saved = UserDefaults.standard.string(forKey: Self.savedStateKey) {
            applyState(saved)
        }
    }

    // MARK: State selection (v1: reminders only, no map)

    /// Use a state's statewide 2026 calendar. Reschedules reminders if they're on.
    func selectState(_ code: String) async {
        applyState(code)
        errorMessage = nil
        if UserDefaults.standard.bool(forKey: ReminderScheduler.remindersKey) {
            _ = await enableReminders()
        }
    }

    /// Fills in the state from the phone's location.
    func detectState() async {
        await run {
            let here = try await self.location.currentLocation()
            let placemark = try await CLGeocoder().reverseGeocodeLocation(here).first
            guard let code = Midterms2026.code(for: placemark?.administrativeArea) else {
                throw LocationError.noAddress
            }
            await self.selectState(code)
        }
    }

    private func applyState(_ code: String) {
        guard Midterms2026.rules(for: code) != nil else { return }
        stateCode = code
        earlyDates = []
        election = Election(id: "2026-general", name: Midterms2026.electionName,
                            electionDay: Midterms2026.electionDay)
        UserDefaults.standard.set(code, forKey: Self.savedStateKey)
    }
    private var earlyDates: [(start: Date, end: Date)] = []

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var electionDate: Date? { election.flatMap { Self.dayFormatter.date(from: $0.electionDay) } }

    // MARK: Loading

    func loadFromCurrentLocation() async {
        await run {
            let here = try await self.location.currentLocation()
            let addr = try await self.location.address(for: here)
            self.address = addr
            try await self.fetch(address: addr)
        }
    }

    func load(address: String) async {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await run { try await self.fetch(address: trimmed) }
    }

    private func run(_ work: @MainActor () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        notice = nil
        defer { isLoading = false }
        do { try await work() } catch { errorMessage = error.localizedDescription }
    }

    private func fetch(address: String) async throws {
        // Which state? Needed for the statewide 2026 calendar even if the API has nothing yet.
        let placemark = try? await CLGeocoder().geocodeAddressString(address).first
        stateCode = Midterms2026.code(for: placemark?.administrativeArea)

        var info: VoterInfoResponse?
        var apiError: Error?
        do { info = try await CivicAPI.voterInfo(address: address) } catch { apiError = error }

        if stateCode == nil { stateCode = Midterms2026.code(for: info?.normalizedInput?.state) }

        guard info != nil || stateCode != nil else {
            throw apiError ?? LocationError.noAddress
        }

        election = info?.election ?? Election(id: "2026-general",
                                              name: Midterms2026.electionName,
                                              electionDay: Midterms2026.electionDay)

        var result: [VotingSite] = []
        var seen = Set<String>()
        var geocodeBudget = 30   // Apple throttles CLGeocoder; most sites include lat/lng anyway.

        func add(_ list: [PollingLocation]?, as kind: SiteKind) async {
            for loc in list ?? [] {
                guard let addr = loc.address?.oneLine, !addr.isEmpty else { continue }
                var coord: CLLocationCoordinate2D?
                if let lat = loc.latitude, let lng = loc.longitude, lat != 0 || lng != 0 {
                    coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                } else if geocodeBudget > 0 {
                    geocodeBudget -= 1
                    coord = try? await CLGeocoder().geocodeAddressString(addr).first?.location?.coordinate
                }
                guard let coord else { continue }
                let site = VotingSite(
                    kind: kind,
                    name: loc.address?.locationName ?? loc.name ?? addr,
                    address: addr,
                    hours: loc.pollingHours,
                    notes: loc.notes,
                    startDate: loc.startDate,
                    endDate: loc.endDate,
                    coordinate: coord)
                if seen.insert(site.id).inserted { result.append(site) }
            }
        }

        await add(info?.pollingLocations, as: .electionDay)
        await add(info?.earlyVoteSites, as: .early)
        await add(info?.dropOffLocations, as: .dropOff)
        sites = result

        // County-specific early voting dates from the API, if published.
        earlyDates = (info?.earlyVoteSites ?? []).compactMap {
            guard let s = $0.startDate.flatMap(Self.dayFormatter.date(from:)),
                  let e = $0.endDate.flatMap(Self.dayFormatter.date(from:)) else { return nil }
            return (s, e)
        }

        // A key problem is never "data not published yet" — say so plainly.
        if let apiError, let civic = apiError as? CivicError {
            switch civic {
            case .missingKey, .badKey: errorMessage = civic.localizedDescription
            case .server: break
            }
        }

        if info?.mailOnly == true {
            notice = "This address votes by mail. Drop-off locations are shown on the map."
        } else if result.isEmpty {
            notice = "Google hasn't published polling places for this address yet — they usually appear a few weeks before Election Day. Reminders use your state's official 2026 dates in the meantime."
        }

        // Refresh reminders if they were already on (e.g. dates changed).
        if UserDefaults.standard.bool(forKey: ReminderScheduler.remindersKey) {
            _ = await enableReminders()
        }
    }

    /// Human-readable summary of the statewide calendar, for the panel.
    var stateSummary: String? {
        guard let rules = stateRules else { return nil }
        let day0 = Calendar.current.startOfDay(for: electionDate ?? Date())
        func time(_ m: Int) -> String {
            day0.addingTimeInterval(TimeInterval(m * 60)).formatted(date: .omitted, time: .shortened)
        }
        func md(_ ymd: String) -> String {
            Self.dayFormatter.date(from: ymd)?.formatted(.dateTime.month(.abbreviated).day()) ?? ymd
        }
        var lines: [String] = []
        if let s = rules.earlyStart, let e = rules.earlyEnd {
            lines.append("\(rules.name) early voting: \(md(s)) – \(md(e))")
        } else {
            lines.append("\(rules.name): no early voting without an excuse")
        }
        lines.append("Election Day polls: \(time(rules.pollsOpen)) – \(time(rules.pollsClose))")
        if let note = rules.note { lines.append(note) }
        return lines.joined(separator: "\n")
    }

    // MARK: Reminders

    /// Returns true if reminders were scheduled.
    func enableReminders() async -> Bool {
        guard let election, let eday = electionDate else {
            errorMessage = "Look up your voting locations first so the app knows the election dates."
            return false
        }
        guard await ReminderScheduler.requestPermission() else {
            errorMessage = "Notifications are off for this app. Turn them on in Settings › Notifications."
            return false
        }

        let rules = stateRules
        var start = earlyDates.map(\.start).min()
        var end = earlyDates.map(\.end).max()
        if start == nil || end == nil {
            // No county data yet: use the statewide 2026 calendar.
            start = rules?.earlyStart.flatMap(Self.dayFormatter.date(from:))
            end = rules?.earlyEnd.flatMap(Self.dayFormatter.date(from:))
        }
        if rules == nil && earlyDates.isEmpty {
            notice = "Couldn't tell which state this address is in, so only Election Day reminders (7 AM – 7 PM) are set."
        }

        await ReminderScheduler.schedule(earlyStart: start, earlyEnd: end,
                                         electionDay: eday, electionName: election.name,
                                         pollsOpen: rules?.pollsOpen ?? 7 * 60,
                                         pollsClose: rules?.pollsClose ?? 19 * 60,
                                         allMail: rules?.allMail ?? false,
                                         plan: plan)
        UserDefaults.standard.set(true, forKey: ReminderScheduler.remindersKey)
        return true
    }

    // MARK: Voting plan

    /// Saves the plan and turns on reminders, including hourly ones on the planned day.
    func savePlan(_ newPlan: VotingPlan) async -> Bool {
        errorMessage = nil
        plan = newPlan
        VotingPlanStore.save(newPlan)
        return await enableReminders()
    }

    func clearPlan() async {
        plan = nil
        VotingPlanStore.clear()
        if UserDefaults.standard.bool(forKey: ReminderScheduler.remindersKey) {
            _ = await enableReminders()
        }
    }

    func disableReminders() {
        ReminderScheduler.cancelAll()
        UserDefaults.standard.set(false, forKey: ReminderScheduler.remindersKey)
    }
}
