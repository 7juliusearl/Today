import Foundation
import CoreLocation

// Public feeds only. Calendar data and personal files never enter these requests.
@MainActor final class DashboardExtras: NSObject, @preconcurrency CLLocationManagerDelegate {
    struct Verse: Codable {
        let text: String
        let reference: String
        let version: String
    }
    struct Weather: Encodable {
        var temperature: Double?
        var code: Int?
        var message = "Fetching weather…"
    }
    var verse = Verse(text: "This is the day which the LORD hath made; we will rejoice and be glad in it.", reference: "Psalm 118:24", version: "KJV · Offline verse")
    var weather = Weather()
    var onChange: (() -> Void)?
    private let location = CLLocationManager()
    private var lastVerseAttempt: Date = .distantPast
    private var verseDay: Date?
    private var lastWeatherAttempt: Date = .distantPast
    private var locating = false
    private var fetchingWeather = false

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var locationAuthorized: Bool {
        location.authorizationStatus == .authorizedAlways
    }
    var locationDenied: Bool {
        [.denied, .restricted].contains(location.authorizationStatus)
    }
    func requestLocationAccess() {
        location.requestWhenInUseAuthorization()
    }

    var weatherBusy: Bool { locating || fetchingWeather }

    func retryWeather() {
        guard locationAuthorized, !weatherBusy else { return }
        lastWeatherAttempt = .distantPast
        weather.message = "Fetching weather…"
        refresh()
        onChange?()
    }

    func refresh() {
        let now = Date()
        if verseDay != Calendar.current.startOfDay(for: now), now.timeIntervalSince(lastVerseAttempt) > 300 {
            lastVerseAttempt = now
            Task {
                do {
                    struct Feed: Decodable {
                        struct Container: Decodable { let details: Verse }
                        let verse: Container
                    }
                    let feed: Feed = try await getJSON("https://beta.ourmanna.com/api/v1/get/?format=json&order=daily")
                    guard !feed.verse.details.text.isEmpty else { return }
                    verse = feed.verse.details
                    verseDay = Calendar.current.startOfDay(for: now)
                    onChange?()
                } catch { /* Keep the readable offline verse when unavailable. */ }
            }
        }
        guard now.timeIntervalSince(lastWeatherAttempt) > 1800, !locating, !fetchingWeather else { return }
        lastWeatherAttempt = now
        switch location.authorizationStatus {
        case .notDetermined:
            weather.message = "Enable location in Settings for weather"
        case .authorizedAlways, .authorizedWhenInUse:
            startLocation()
        default:
            weather.message = "Enable location in Settings for weather"
        }
    }

    private func startLocation() {
        guard !locating else { return }
        locating = true
        location.startUpdatingLocation()
        Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if locating {
                location.stopUpdatingLocation()
                locating = false
                weather.message = "Location unavailable"
                onChange?()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onChange?()
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            lastWeatherAttempt = .distantPast
            refresh()
        case .denied, .restricted:
            manager.stopUpdatingLocation()
            locating = false
            weather = Weather(message: "Enable location in Settings for weather")
            onChange?()
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        manager.stopUpdatingLocation()
        locating = false
        weather.message = "Location unavailable"
        onChange?()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let point = locations.last, point.horizontalAccuracy >= 0, !fetchingWeather else { return }
        manager.stopUpdatingLocation()
        locating = false
        fetchingWeather = true
        // City-scale precision is sufficient for weather.
        let lat = (point.coordinate.latitude * 100).rounded() / 100
        let lon = (point.coordinate.longitude * 100).rounded() / 100
        Task {
            defer { fetchingWeather = false }
            do {
                struct Forecast: Decodable {
                    struct Current: Decodable { let temperature_2m: Double; let weather_code: Int }
                    let current: Current
                }
                let feed: Forecast = try await getJSON("https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code&temperature_unit=fahrenheit")
                weather = Weather(temperature: feed.current.temperature_2m, code: feed.current.weather_code, message: "")
            } catch { weather.message = "Weather unavailable" }
            onChange?()
        }
    }

    private func getJSON<T: Decodable>(_ address: String) async throws -> T {
        var request = URLRequest(url: URL(string: address)!)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
