import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    @Published var location: CLLocation?
    @Published var locationDescription: String?
    @Published var country: String?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }
    
    func requestLocation() async {
        if CLLocationManager.locationServicesEnabled() {
            if locationManager.authorizationStatus == .notDetermined {
                await withCheckedContinuation { continuation in
                    locationManager.requestWhenInUseAuthorization()
                    continuation.resume()
                }
            } else {
                locationManager.startUpdatingLocation()
            }
        } else {
            print("Location services are disabled.")
            // Handle this case, perhaps with an alert to the user
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            print("Location access denied.")
            // Handle denial or restriction (e.g., show an alert)
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        self.location = location
        locationManager.stopUpdatingLocation()
        fetchAddress(for: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Failed to get location: \(error.localizedDescription)")
        // Provide fallback or alert the user
    }

    private func fetchAddress(for location: CLLocation) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            if let error = error {
                print("Failed to reverse geocode location: \(error.localizedDescription)")
                return
            }
            guard let placemark = placemarks?.first else { return }
            self?.locationDescription = "\(placemark.thoroughfare ?? ""), \(placemark.locality ?? "")"
            self?.country = placemark.country
        }
    }
}
