import Foundation
import CoreLocation
import Combine

@MainActor
public final class WiFiLocationAuthorizer: NSObject, ObservableObject, CLLocationManagerDelegate, Sendable {
    public static let shared = WiFiLocationAuthorizer()

    private let locationManager = CLLocationManager()
    @Published public var authorizationStatus: CLAuthorizationStatus

    public override init() {
        self.authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
    }

    public var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways
    }

    public var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    public var isNotDetermined: Bool {
        authorizationStatus == .notDetermined
    }

    public func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }
}
