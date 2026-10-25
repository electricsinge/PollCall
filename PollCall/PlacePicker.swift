import SwiftUI
import MapKit
import CoreLocation

/// A place shown on the picker map.
struct PlaceCandidate: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let source: PlaceSource
    let hours: String?

    var planned: PlannedPlace {
        PlannedPlace(name: name, address: address,
                     latitude: coordinate.latitude, longitude: coordinate.longitude,
                     source: source)
    }

    static func == (a: PlaceCandidate, b: PlaceCandidate) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Map for choosing where you'll vote: official locations for your address,
/// plus Apple Maps search near you.
struct PlacePicker: View {
    @Binding var detent: PresentationDetent
    let onPick: (PlannedPlace) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("homeAddress") private var homeAddress = ""

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var region: MKCoordinateRegion?
    @State private var candidates: [PlaceCandidate] = []
    @State private var selectedID: String?
    @State private var query = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var didInitialSearch = false
    @State private var locationManager = CLLocationManager()

    private var selected: PlaceCandidate? { candidates.first { $0.id == selectedID } }

    var body: some View {
        Map(position: $camera, selection: $selectedID) {
            UserAnnotation()
            ForEach(candidates) { place in
                Marker(place.name, systemImage: place.source.symbol, coordinate: place.coordinate)
                    .tint(place.source.color)
                    .tag(place.id)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            region = context.region
            // Search once, automatically, as soon as the map is zoomed to the user's area.
            if !didInitialSearch && isLocalArea(context.region) {
                didInitialSearch = true
                Task { await searchNearby() }
            }
        }
        .safeAreaInset(edge: .top) { searchBar }
        .safeAreaInset(edge: .bottom) { bottomPanel }
        .navigationTitle("Where you'll vote")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear {
            detent = .large
            locationManager.requestWhenInUseAuthorization()
        }
    }

    // MARK: Panels

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search, e.g. library or city hall", text: $query)
                .submitLabel(.search)
                .onSubmit { Task { await search([query], replacingSearchResults: true) } }
            if isWorking {
                ProgressView()
            } else {
                Button("Search here") { Task { await searchNearby() } }
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let place = selected {
                selectedCard(place)
            } else {
                officialFinder
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var officialFinder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Official locations for your address")
                .font(.subheadline.weight(.semibold))
            HStack {
                TextField("Address where you're registered", text: $homeAddress)
                    .textContentType(.fullStreetAddress)
                    .submitLabel(.search)
                    .onSubmit { Task { await findOfficial() } }
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                Button("Find") { Task { await findOfficial() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.ink)
                    .disabled(homeAddress.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            }
            Text("Or tap a pin from the map search. Map results aren't official voting locations, so double-check them.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func selectedCard(_ place: PlaceCandidate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(place.source.label, systemImage: place.source.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(place.source == .early ? Brand.onMarigold : place.source.color)
            Text(place.name).font(.headline)
            if !place.address.isEmpty {
                Text(place.address).font(.subheadline).foregroundStyle(.secondary)
            }
            if let hours = place.hours, !hours.isEmpty {
                Text(hours).font(.caption).foregroundStyle(.secondary)
            }
            if let caution = place.source.caution {
                Text(caution).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Back") { selectedID = nil }
                    .buttonStyle(.bordered)
                Button {
                    onPick(place.planned)
                    detent = .large
                    dismiss()
                } label: {
                    Text("Vote here").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.ink)
            }
            .padding(.top, 4)
        }
    }

    // MARK: Searching

    private func isLocalArea(_ region: MKCoordinateRegion) -> Bool {
        region.span.latitudeDelta < 1.5 && region.span.longitudeDelta < 1.5
    }

    private func searchNearby() async {
        await search(["polling place", "early voting", "election office", "board of elections"],
                     replacingSearchResults: true)
    }

    /// Apple Maps search in the visible area. Keeps any official locations already shown.
    private func search(_ queries: [String], replacingSearchResults: Bool) async {
        guard let region, isLocalArea(region) else {
            message = "Zoom in on your area first, then tap Search here."
            return
        }
        isWorking = true
        defer { isWorking = false }

        var found = replacingSearchResults ? candidates.filter { $0.source != .search } : candidates
        var added = 0
        for q in queries {
            let text = q.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            request.region = region
            request.resultTypes = .pointOfInterest
            guard let response = try? await MKLocalSearch(request: request).start() else { continue }
            for item in response.mapItems {
                let coord = item.placemark.coordinate
                let name = item.name ?? "Unnamed place"
                let id = "search|\(name)|\(String(format: "%.5f,%.5f", coord.latitude, coord.longitude))"
                guard !found.contains(where: { $0.id == id }) else { continue }
                found.append(PlaceCandidate(id: id, name: name, address: item.placemark.title ?? "",
                                            coordinate: coord, source: .search, hours: nil))
                added += 1
            }
        }
        candidates = found
        selectedID = nil
        message = added == 0
            ? "No places found here. Try another search, or find official locations for your address below."
            : nil
    }

    /// Official polling places, early voting sites and drop boxes from Google's Civic Information API.
    private func findOfficial() async {
        let address = homeAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let info = try await CivicAPI.voterInfo(address: address)
            var official: [PlaceCandidate] = []
            official += await convert(info.pollingLocations, as: .electionDay)
            official += await convert(info.earlyVoteSites, as: .early)
            official += await convert(info.dropOffLocations, as: .dropOff)

            if official.isEmpty {
                message = "No official locations are published for this address yet. Check vote.gov or your county election office, or search the map."
            } else {
                message = nil
                candidates = official + candidates.filter { $0.source == .search }
                selectedID = nil
                camera = .automatic
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func convert(_ list: [PollingLocation]?, as source: PlaceSource) async -> [PlaceCandidate] {
        var result: [PlaceCandidate] = []
        var geocodeBudget = 10
        for loc in list ?? [] {
            guard let address = loc.address?.oneLine, !address.isEmpty else { continue }
            var coord: CLLocationCoordinate2D?
            if let lat = loc.latitude, let lng = loc.longitude, lat != 0 || lng != 0 {
                coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            } else if geocodeBudget > 0 {
                geocodeBudget -= 1
                coord = try? await CLGeocoder().geocodeAddressString(address).first?.location?.coordinate
            }
            guard let coord else { continue }
            let id = "\(source.rawValue)|\(address)"
            guard !result.contains(where: { $0.id == id }) else { continue }
            result.append(PlaceCandidate(id: id,
                                         name: loc.address?.locationName ?? loc.name ?? address,
                                         address: address, coordinate: coord,
                                         source: source, hours: loc.pollingHours))
        }
        return result
    }
}
