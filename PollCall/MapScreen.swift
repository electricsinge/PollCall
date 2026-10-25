import SwiftUI
import MapKit

/// Map of polling places. Not shown in v1 — swap it back in once counties publish locations.
struct MapScreen: View {
    @EnvironmentObject private var model: VotingModel
    @AppStorage(ReminderScheduler.hasVotedKey) private var hasVoted = false
    @AppStorage(ReminderScheduler.remindersKey) private var remindersOn = false

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedID: String?
    @State private var showList = false
    @State private var addressField = ""
    @FocusState private var addressFocused: Bool

    private var selectedSite: Binding<VotingSite?> {
        Binding(
            get: { model.sites.first { $0.id == selectedID } },
            set: { if $0 == nil { selectedID = nil } })
    }

    var body: some View {
        Map(position: $camera, selection: $selectedID) {
            UserAnnotation()
            ForEach(model.sites) { site in
                Marker(site.name, systemImage: site.kind.symbol, coordinate: site.coordinate)
                    .tint(site.kind.color)
                    .tag(site.id)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .safeAreaInset(edge: .top) { searchBar }
        .safeAreaInset(edge: .bottom) { panel }
        .sheet(item: selectedSite) { SiteDetail(site: $0).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showList) { siteList }
        .onChange(of: model.sites) { withAnimation { camera = .automatic } }
        .onChange(of: model.address) { addressField = model.address }
        .task { if model.sites.isEmpty { await model.loadFromCurrentLocation() } }
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "house")
                .foregroundStyle(.secondary)
            TextField("Your registered voting address", text: $addressField)
                .textContentType(.fullStreetAddress)
                .submitLabel(.search)
                .focused($addressFocused)
                .onSubmit { Task { await model.load(address: addressField) } }
            if model.isLoading {
                ProgressView()
            } else {
                Button {
                    addressFocused = false
                    Task { await model.loadFromCurrentLocation() }
                } label: {
                    Image(systemName: "location.fill")
                }
                .accessibilityLabel("Use my current location")
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }

    // MARK: Bottom panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let election = model.election {
                VStack(alignment: .leading, spacing: 2) {
                    Text(election.name).font(.headline)
                    if let day = model.electionDate {
                        Text("Election Day is \(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let summary = model.stateSummary {
                        Text(summary)
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
            }

            if let error = model.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            if let notice = model.notice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
            }

            if hasVoted {
                VotedBadge(stickerSize: 88) { hasVoted = false }
            } else {
                Toggle(isOn: Binding(
                    get: { remindersOn },
                    set: { on in
                        remindersOn = on            // move the switch immediately
                        Task { await setReminders(on) }
                    })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remind me to vote")
                        Text(model.election == nil
                             ? "Look up your address first so the app knows the election dates"
                             : "Daily during early voting, hourly on Election Day")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(model.election == nil)

                IVotedButton {
                    ReminderScheduler.markVoted()
                    hasVoted = true
                    remindersOn = false
                }
                .sensoryFeedback(.success, trigger: hasVoted)
            }

            if !model.sites.isEmpty {
                Button("See all \(model.sites.count) locations as a list") { showList = true }
                    .font(.footnote)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal)
    }

    private func setReminders(_ on: Bool) async {
        if on {
            remindersOn = await model.enableReminders()
        } else {
            model.disableReminders()
            remindersOn = false
        }
    }

    // MARK: List

    private var siteList: some View {
        NavigationStack {
            List {
                ForEach(SiteKind.allCases, id: \.self) { kind in
                    let group = model.sites.filter { $0.kind == kind }
                    if !group.isEmpty {
                        Section(kind.rawValue) {
                            ForEach(group) { site in
                                Button {
                                    showList = false
                                    selectedID = site.id
                                    camera = .region(MKCoordinateRegion(
                                        center: site.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(site.name).foregroundStyle(.primary)
                                        Text(site.address).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Voting locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { showList = false } }
        }
    }
}

// MARK: - Site detail sheet

struct SiteDetail: View {
    let site: VotingSite
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label(site.kind.rawValue, systemImage: site.kind.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(site.kind.color)
                Text(site.name).font(.title2.bold())
                Text(site.address).foregroundStyle(.secondary)

                if let start = site.startDate, let end = site.endDate {
                    Text("Open \(pretty(start)) – \(pretty(end))").font(.subheadline)
                }
                if let hours = site.hours, !hours.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hours").font(.headline)
                        Text(hours).font(.subheadline)
                    }
                }
                if let notes = site.notes, !notes.isEmpty {
                    Text(notes).font(.footnote).foregroundStyle(.secondary)
                }

                Button {
                    let c = site.coordinate
                    if let url = URL(string: "http://maps.apple.com/?daddr=\(c.latitude),\(c.longitude)") {
                        openURL(url)
                    }
                } label: {
                    Label("Get directions", systemImage: "car.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(site.kind.color)
            }
            .padding()
        }
    }

    private func pretty(_ ymd: String) -> String {
        guard let d = VotingModel.dayFormatter.date(from: ymd) else { return ymd }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
}
