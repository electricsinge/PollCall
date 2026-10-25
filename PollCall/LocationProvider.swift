import CoreLocation

enum LocationError: LocalizedError {
    case denied, noAddress
    var errorDescription: String? {
        switch self {
        case .denied: return "Location access is off. Pick your state from the list instead."
        case .noAddress: return "Couldn't tell which state you're in. Pick it from the list instead."
        }
    }
}

/// One-shot async wrapper around CLLocationManager.
/// Everything runs on the main actor; CLLocationManager calls its delegate on the
/// thread it was created on (main), so no hopping between threads is needed.
@MainActor
final class LocationProvider: NSObject {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CLLocation, Error>) in
            if let old = continuation { old.resume(throwing: CancellationError()) }
            continuation = cont
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()   // answer arrives in the delegate
            case .denied, .restricted:
                fail(LocationError.denied)
            default:
                manager.requestLocation()
            }
        }
    }

    /// Street address for a location, formatted for the Civic API.
    func address(for location: CLLocation) async throws -> String {
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
        guard let p = placemarks.first else { throw LocationError.noAddress }
        let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let stateZip = [p.administrativeArea, p.postalCode].compactMap { $0 }.joined(separator: " ")
        let result = [street, p.locality ?? "", stateZip].filter { !$0.isEmpty }.joined(separator: ", ")
        guard !result.isEmpty else { throw LocationError.noAddress }
        return result
    }

    fileprivate func succeed(_ location: CLLocation) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    fileprivate func fail(_ error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    fileprivate func authorizationChanged() {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: fail(LocationError.denied)
        default: break
        }
    }
}

extension LocationProvider: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationChanged()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last { succeed(location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        fail(error)
    }
}
