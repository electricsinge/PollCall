import SwiftUI
import EventKit
import EventKitUI

/// Apple's "New Event" screen, pre-filled with the voting plan.
/// On iOS 17+ this screen runs outside the app, so it needs no calendar permission.
struct CalendarEventEditor: UIViewControllerRepresentable {
    let plan: VotingPlan
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "Vote"
        event.startDate = plan.date
        event.endDate = plan.date.addingTimeInterval(60 * 60)
        event.addAlarm(EKAlarm(relativeOffset: -60 * 60))

        var notes = ["Your voting plan from Poll Call."]
        if let place = plan.place {
            let location = EKStructuredLocation(title: "\(place.name), \(place.address)")
            location.geoLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            event.structuredLocation = location
            event.url = place.mapsURL

            notes.append(place.name)
            notes.append(place.address)
            if let url = place.mapsURL { notes.append("Directions: \(url.absoluteString)") }
            if let caution = place.source.caution { notes.append(caution) }
        }
        notes.append("Confirm your voting location and what to bring at vote.gov.")
        event.notes = notes.joined(separator: "\n")

        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }

        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }
}
