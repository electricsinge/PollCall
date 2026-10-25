import SwiftUI
import CoreLocation

/// Where a planned voting location came from. Decides the label, color and warnings.
enum PlaceSource: String, Codable {
    case electionDay   // official Election Day polling place (Google Civic API)
    case early         // official early voting site (Google Civic API)
    case dropOff       // official ballot drop box (Google Civic API)
    case search        // Apple Maps search result: not verified as a voting location

    var label: String {
        switch self {
        case .electionDay: return "Official Election Day polling place"
        case .early: return "Official early voting site"
        case .dropOff: return "Official ballot drop box"
        case .search: return "Apple Maps result"
        }
    }

    var symbol: String {
        switch self {
        case .electionDay: return "checkmark.rectangle.stack.fill"
        case .early: return "calendar"
        case .dropOff: return "tray.and.arrow.down.fill"
        case .search: return "mappin"
        }
    }

    var color: Color {
        switch self {
        case .electionDay: return Brand.ink
        case .early: return Brand.marigold
        case .dropOff, .search: return Brand.slate
        }
    }

    /// A caution to show for this kind of place, if any.
    var caution: String? {
        switch self {
        case .search:
            return "This is a map search result, not an official voting location. Confirm you can vote here at vote.gov or with your county election office."
        case .dropOff:
            return "Drop boxes are for returning mail ballots, not for voting in person."
        default:
            return nil
        }
    }
}

struct PlannedPlace: Codable, Equatable {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var source: PlaceSource

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Opens Apple Maps with directions to this place.
    var mapsURL: URL? {
        var c = URLComponents(string: "https://maps.apple.com/")
        c?.queryItems = [
            URLQueryItem(name: "daddr", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "q", value: name)
        ]
        return c?.url
    }
}

/// When and where the user plans to vote.
struct VotingPlan: Codable, Equatable {
    var date: Date
    var place: PlannedPlace?
}

enum VotingPlanStore {
    private static let key = "votingPlan"

    static func load() -> VotingPlan? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(VotingPlan.self, from: data)
    }

    static func save(_ plan: VotingPlan) {
        if let data = try? JSONEncoder().encode(plan) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
