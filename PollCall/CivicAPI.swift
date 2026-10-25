import Foundation

// MARK: - Google Civic Information API (voterinfo endpoint)
// Docs: https://developers.google.com/civic-information/docs/v2/elections/voterInfoQuery

struct VoterInfoResponse: Decodable {
    let election: Election?
    let pollingLocations: [PollingLocation]?
    let earlyVoteSites: [PollingLocation]?
    let dropOffLocations: [PollingLocation]?
    let mailOnly: Bool?
    let normalizedInput: CivicAddress?
}

struct Election: Decodable, Equatable {
    let id: String
    let name: String
    let electionDay: String   // "yyyy-MM-dd"
}

struct PollingLocation: Decodable {
    let address: CivicAddress?
    let name: String?
    let pollingHours: String?
    let notes: String?
    let startDate: String?    // early voting sites usually have these
    let endDate: String?
    let latitude: Double?
    let longitude: Double?
}

struct CivicAddress: Decodable {
    let locationName: String?
    let line1: String?
    let line2: String?
    let city: String?
    let state: String?
    let zip: String?

    var oneLine: String {
        [line1, line2, city, state, zip]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

private struct APIErrorEnvelope: Decodable {
    struct Body: Decodable { let message: String }
    let error: Body
}

enum CivicError: LocalizedError {
    case missingKey
    case badKey(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "No Google Civic API key found. Add it as CivicAPIKey in Info.plist (or project.yml), then rebuild."
        case .badKey(let message):
            return "Google rejected the API key: \(message)"
        case .server(let message):
            return message
        }
    }
}

enum CivicAPI {
    static var apiKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "CivicAPIKey") as? String) ?? ""
    }

    /// Looks up polling places, early voting sites and drop boxes for a *registered* address.
    static func voterInfo(address: String) async throws -> VoterInfoResponse {
        guard !apiKey.isEmpty else { throw CivicError.missingKey }

        var components = URLComponents(string: "https://www.googleapis.com/civicinfo/v2/voterinfo")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "address", value: address),
            URLQueryItem(name: "returnAllAvailableData", value: "true")
        ]

        var request = URLRequest(url: components.url!)
        // Required if the key is restricted to iOS apps in Google Cloud Console.
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error.message
                ?? "HTTP \(http.statusCode)"
            if http.statusCode == 401 || http.statusCode == 403 {
                throw CivicError.badKey(message)
            }
            throw CivicError.server(message)
        }
        return try JSONDecoder().decode(VoterInfoResponse.self, from: data)
    }
}
