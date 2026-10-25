import Foundation

/// Statewide early-voting windows and Election Day poll hours for the
/// November 3, 2026 general (midterm) election.
///
/// These are *fallbacks*. When the Google Civic API has published county data
/// for the user's address, those dates are used instead.
///
/// Sources (as of Sept 2026): state election calendars / statutes via CEIR's
/// "Dates for 2026 Early In-Person and Mail Voting", NCSL, VoteTexas.gov,
/// DC Board of Elections, and published 2026 poll closing times.
/// Where counties choose their own dates, the statewide *required* window is used.
/// Poll hours are local time; where they vary by county/town, the latest common
/// opening and earliest common closing are used so reminders never say polls are
/// open when they might not be.
struct StateVotingRules {
    let name: String
    let earlyStart: String?     // "yyyy-MM-dd", nil = no no-excuse early voting
    let earlyEnd: String?
    let pollsOpen: Int          // minutes after midnight, local time
    let pollsClose: Int
    let allMail: Bool           // every active voter is mailed a ballot
    let note: String?
}

enum Midterms2026 {
    static let electionDay = "2026-11-03"
    static let electionName = "2026 General Election"

    static func rules(for stateOrCode: String?) -> StateVotingRules? {
        guard let raw = stateOrCode?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let r = byCode[raw.uppercased()] { return r }
        return byCode.values.first { $0.name.caseInsensitiveCompare(raw) == .orderedSame }
    }

    static func code(for stateOrCode: String?) -> String? {
        guard let raw = stateOrCode?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if byCode[raw.uppercased()] != nil { return raw.uppercased() }
        return byCode.first { $0.value.name.caseInsensitiveCompare(raw) == .orderedSame }?.key
    }

    private static func r(_ name: String, _ start: String?, _ end: String?,
                          open: (Int, Int), close: (Int, Int),
                          mail: Bool = false, note: String? = nil) -> StateVotingRules {
        StateVotingRules(name: name,
                         earlyStart: start.map { "2026-\($0)" },
                         earlyEnd: end.map { "2026-\($0)" },
                         pollsOpen: open.0 * 60 + open.1,
                         pollsClose: close.0 * 60 + close.1,
                         allMail: mail, note: note)
    }

    // Early dates are "MM-dd" in 2026. Poll hours are (hour, minute), 24-hour clock.
    static let byCode: [String: StateVotingRules] = [
        "AL": r("Alabama", nil, nil, open: (7, 0), close: (19, 0),
                note: "No early in-person voting without an excuse."),
        "AK": r("Alaska", "10-19", "11-02", open: (7, 0), close: (20, 0)),
        "AZ": r("Arizona", "10-07", "10-30", open: (6, 0), close: (19, 0)),
        "AR": r("Arkansas", "10-19", "11-02", open: (7, 30), close: (19, 30)),
        "CA": r("California", "10-05", "11-02", open: (7, 0), close: (20, 0), mail: true),
        "CO": r("Colorado", "10-19", "11-02", open: (7, 0), close: (19, 0), mail: true),
        "CT": r("Connecticut", "10-19", "11-01", open: (6, 0), close: (20, 0)),
        "DE": r("Delaware", "10-24", "11-01", open: (7, 0), close: (20, 0)),
        "DC": r("District of Columbia", "10-26", "11-01", open: (7, 0), close: (20, 0), mail: true),
        "FL": r("Florida", "10-24", "10-31", open: (7, 0), close: (19, 0),
                note: "Some counties open early voting as soon as Oct 19."),
        "GA": r("Georgia", "10-12", "10-30", open: (7, 0), close: (19, 0)),
        "HI": r("Hawaii", "10-20", "11-02", open: (7, 0), close: (19, 0), mail: true),
        "ID": r("Idaho", "09-18", "10-30", open: (8, 0), close: (20, 0),
                note: "Early voting is in-person absentee at the county clerk."),
        "IL": r("Illinois", "09-24", "11-02", open: (6, 0), close: (19, 0)),
        "IN": r("Indiana", "10-06", "11-02", open: (6, 0), close: (18, 0)),
        "IA": r("Iowa", "10-14", "11-02", open: (7, 0), close: (20, 0)),
        "KS": r("Kansas", "10-14", "11-02", open: (7, 0), close: (19, 0),
                note: "Counties set early voting dates and may keep polls open until 8 PM."),
        "KY": r("Kentucky", "10-29", "10-31", open: (6, 0), close: (18, 0)),
        "LA": r("Louisiana", "10-20", "10-27", open: (6, 0), close: (20, 0)),
        "ME": r("Maine", "10-05", "10-29", open: (8, 0), close: (20, 0),
                note: "Early voting is in-person absentee at your town clerk; opening times vary by town."),
        "MD": r("Maryland", "10-22", "10-29", open: (7, 0), close: (20, 0)),
        "MA": r("Massachusetts", "10-17", "10-30", open: (7, 0), close: (20, 0)),
        "MI": r("Michigan", "10-24", "11-01", open: (7, 0), close: (20, 0)),
        "MN": r("Minnesota", "09-18", "11-02", open: (7, 0), close: (20, 0)),
        "MS": r("Mississippi", nil, nil, open: (7, 0), close: (19, 0),
                note: "No early in-person voting without an excuse."),
        "MO": r("Missouri", "10-20", "11-02", open: (6, 0), close: (19, 0)),
        "MT": r("Montana", "10-05", "11-02", open: (7, 0), close: (20, 0)),
        "NE": r("Nebraska", "10-05", "11-02", open: (8, 0), close: (19, 0),
                note: "Polls run 8 AM–8 PM Central or 7 AM–7 PM Mountain."),
        "NV": r("Nevada", "10-17", "10-30", open: (7, 0), close: (19, 0), mail: true),
        "NH": r("New Hampshire", nil, nil, open: (8, 0), close: (19, 0),
                note: "No early in-person voting without an excuse. Each town sets its own poll hours."),
        "NJ": r("New Jersey", "10-24", "11-01", open: (6, 0), close: (20, 0)),
        "NM": r("New Mexico", "10-06", "10-31", open: (7, 0), close: (19, 0)),
        "NY": r("New York", "10-24", "11-01", open: (6, 0), close: (21, 0)),
        "NC": r("North Carolina", "10-15", "10-31", open: (6, 30), close: (19, 30)),
        "ND": r("North Dakota", "10-19", "11-02", open: (9, 0), close: (19, 0),
                note: "Counties choose early voting dates and set poll hours between 7 AM and 9 PM."),
        "OH": r("Ohio", "10-06", "11-01", open: (6, 30), close: (19, 30)),
        "OK": r("Oklahoma", "10-28", "10-31", open: (7, 0), close: (19, 0)),
        "OR": r("Oregon", "10-16", "11-02", open: (8, 0), close: (20, 0), mail: true,
                note: "Oregon votes by mail. Election Day times are for ballot drop sites."),
        "PA": r("Pennsylvania", "10-20", "10-27", open: (7, 0), close: (20, 0),
                note: "Early voting means requesting and casting a mail ballot at your county office."),
        "RI": r("Rhode Island", "10-14", "11-02", open: (7, 0), close: (20, 0)),
        "SC": r("South Carolina", "10-19", "10-31", open: (7, 0), close: (19, 0)),
        "SD": r("South Dakota", "09-18", "11-02", open: (7, 0), close: (19, 0)),
        "TN": r("Tennessee", "10-14", "10-29", open: (8, 0), close: (19, 0),
                note: "Polls close 8 PM Eastern or 7 PM Central; opening times vary by county."),
        "TX": r("Texas", "10-19", "10-30", open: (7, 0), close: (19, 0)),
        "UT": r("Utah", "10-20", "10-30", open: (7, 0), close: (20, 0), mail: true),
        "VT": r("Vermont", "09-19", "11-02", open: (10, 0), close: (19, 0), mail: true,
                note: "Towns open polls between 5 and 10 AM."),
        "VA": r("Virginia", "09-18", "10-31", open: (6, 0), close: (19, 0)),
        "WA": r("Washington", "10-16", "11-02", open: (8, 0), close: (20, 0), mail: true,
                note: "Washington votes by mail. Election Day times are for voting centers and drop boxes."),
        "WV": r("West Virginia", "10-21", "10-31", open: (6, 30), close: (19, 30)),
        "WI": r("Wisconsin", "10-20", "11-01", open: (7, 0), close: (20, 0)),
        "WY": r("Wyoming", "10-06", "11-02", open: (7, 0), close: (19, 0)),
    ]
}
