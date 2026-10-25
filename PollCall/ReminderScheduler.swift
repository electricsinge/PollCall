import Foundation
import UserNotifications

/// Schedules local notifications:
///  • once a day during early voting
///  • every hour on Election Day
///  • every hour on the day of the user's voting plan, plus a heads-up before the planned time
/// …until the user taps "I voted" (in the app or on the notification).
///
/// iOS keeps at most 64 pending local notifications per app, so everything is
/// scheduled up front: ~13–16 Election Day reminders plus up to 46 early-voting days (the longest window, MN/SD/VA/ID).
enum ReminderScheduler {
    static let category = "VOTE_REMINDER"
    static let votedAction = "I_VOTED"
    static let hasVotedKey = "hasVoted"
    static let remindersKey = "remindersEnabled"
    static let votedAtKey = "votedAt"

    /// Time of the daily early-voting reminder.
    static let dailyHour = 9
    /// Hourly reminders on an early-voting plan day run from this hour through planDayLastHour.
    /// (Early voting site hours vary, so these are a reasonable daytime window.)
    static let planDayFirstHour = 8
    static let planDayLastHour = 19

    private static let maxPending = 64

    static func registerCategories() {
        let voted = UNNotificationAction(identifier: votedAction, title: "I voted", options: [])
        let category = UNNotificationCategory(identifier: category, actions: [voted],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// - Parameters:
    ///   - pollsOpen / pollsClose: Election Day poll hours, minutes after local midnight.
    static func schedule(earlyStart: Date?, earlyEnd: Date?, electionDay: Date, electionName: String,
                         pollsOpen: Int, pollsClose: Int, allMail: Bool,
                         plan: VotingPlan? = nil) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard !UserDefaults.standard.bool(forKey: hasVotedKey) else { return }

        let cal = Calendar.current
        let now = Date()
        let day0 = cal.startOfDay(for: electionDay)
        let closeTime = day0.addingTimeInterval(TimeInterval(pollsClose * 60))
        let closeText = closeTime.formatted(date: .omitted, time: .shortened)
        var requests: [UNNotificationRequest] = []

        // Details of the user's plan, used in reminder text.
        let planDay = plan.map { cal.startOfDay(for: $0.date) }
        let planTime = plan?.date.formatted(date: .omitted, time: .shortened) ?? ""
        let planWhere = plan?.place.map { " at \($0.name)" } ?? ""
        let planIsElectionDay = planDay == day0

        // Election Day: every hour from opening, plus a last call 30 minutes before close.
        // Added first so they're never crowded out by the 64-notification limit.
        var minute = pollsOpen
        while minute < pollsClose {
            let fire = day0.addingTimeInterval(TimeInterval(minute * 60))
            let left = pollsClose - minute
            if fire > now {
                var body: String
                if minute == pollsOpen {
                    body = allMail ? "Return your ballot or vote in person today. Polls close at \(closeText)."
                                   : "Polls are open until \(closeText). Open the app to find your polling place."
                } else if left <= 60 {
                    body = "Polls close at \(closeText). If you're in line at closing time, stay in line — you can still vote."
                } else {
                    body = "Haven't voted yet? Polls close at \(closeText)."
                }
                if planIsElectionDay, left > 60 {
                    body += " Your plan: vote\(planWhere) at \(planTime)."
                }
                requests.append(request(id: "eday-\(minute)", fire: fire, title: "It's Election Day", body: body))
            }
            minute += 60
        }
        let lastCall = day0.addingTimeInterval(TimeInterval((pollsClose - 30) * 60))
        if lastCall > now, (pollsClose - 30 - pollsOpen) % 60 != 0 {
            requests.append(request(id: "eday-lastcall", fire: lastCall, title: "30 minutes left to vote",
                                    body: "Polls close at \(closeText). Get in line now — if you're in line at closing time, you can still vote."))
        }

        // Voting plan: a heads-up 30 minutes before the planned time, and on an
        // early-voting plan day, a reminder every hour until "I voted".
        if let plan, let planDay {
            let headsUp = plan.date.addingTimeInterval(-30 * 60)
            if headsUp > now {
                requests.append(request(id: "plan-headsup", fire: headsUp,
                                        title: "Time to head out and vote",
                                        body: "Your plan: vote\(planWhere) at \(planTime)."))
            }
            if !planIsElectionDay {
                for hour in planDayFirstHour...planDayLastHour {
                    guard let fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: planDay),
                          fire > now else { continue }
                    let body = fire < plan.date
                        ? "Today's the day. Your plan: vote\(planWhere) at \(planTime)."
                        : "Haven't voted yet? Your plan was to vote\(planWhere) today. Tap I voted when you're done."
                    requests.append(request(id: "plan-\(hour)", fire: fire,
                                            title: "Today's your voting day", body: body))
                }
            }
        }

        // Early voting: daily, stopping the day before Election Day.
        if let start = earlyStart, let end = earlyEnd,
           let dayBefore = cal.date(byAdding: .day, value: -1, to: day0) {
            let last = min(cal.startOfDay(for: end), dayBefore)
            var day = cal.startOfDay(for: start)
            while day <= last && requests.count < maxPending {
                if day == planDay {   // the plan-day reminders already cover this day
                    guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                    continue
                }
                if let fire = cal.date(bySettingHour: dailyHour, minute: 0, second: 0, of: day), fire > now {
                    let daysLeft = (cal.dateComponents([.day], from: day, to: last).day ?? 0) + 1
                    let body: String
                    if allMail {
                        body = "Your ballot for \(electionName) can be returned now. You can also vote in person."
                    } else if daysLeft == 1 {
                        body = "Last day of early voting for \(electionName). Skip the Election Day lines."
                    } else {
                        body = "Early voting is open for \(electionName). \(daysLeft) days left to vote early."
                    }
                    requests.append(request(id: "early-\(Int(day.timeIntervalSince1970))", fire: fire,
                                            title: allMail ? "Time to vote" : "Early voting is open", body: body))
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }

        for r in requests.prefix(maxPending) { try? await center.add(r) }
    }

    /// Stops every reminder, scheduled or already delivered.
    static func markVoted() {
        UserDefaults.standard.set(true, forKey: hasVotedKey)
        UserDefaults.standard.set(Date(), forKey: votedAtKey)
        UserDefaults.standard.set(false, forKey: remindersKey)
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private static func request(id: String, fire: Date, title: String, body: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}
