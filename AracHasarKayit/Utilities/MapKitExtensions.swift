import MapKit
import CoreLocation

// MARK: - Driver Cluster Annotation

class DriverClusterAnnotation: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D
    var title: String?
    var drivers: [ShuttleLocation]
    
    init(coordinate: CLLocationCoordinate2D, drivers: [ShuttleLocation]) {
        self.coordinate = coordinate
        self.drivers = drivers
        self.title = "\(drivers.count) Active Drivers"
        super.init()
    }
}

// MARK: - Route Manager

class RouteManager: ObservableObject {
    @Published var currentRoute: MKRoute?
    @Published var routePolyline: MKPolyline?
    @Published var estimatedTime: TimeInterval?
    @Published var estimatedDistance: CLLocationDistance?
    
    func calculateRoute(from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async {
        let sourcePlacemark = MKPlacemark(coordinate: source)
        let destinationPlacemark = MKPlacemark(coordinate: destination)
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: sourcePlacemark)
        request.destination = MKMapItem(placemark: destinationPlacemark)
        request.transportType = .automobile
        
        let directions = MKDirections(request: request)
        
        do {
            let response = try await directions.calculate()
            
            if let route = response.routes.first {
                await MainActor.run {
                    self.currentRoute = route
                    self.routePolyline = route.polyline
                    self.estimatedTime = route.expectedTravelTime
                    self.estimatedDistance = route.distance
                }
                
                print("✅ Route calculated: \(route.distance/1000) km, ETA: \(route.expectedTravelTime/60) min")
            }
        } catch {
            print("❌ Route calculation error: \(error)")
        }
    }
    
    func clearRoute() {
        currentRoute = nil
        routePolyline = nil
        estimatedTime = nil
        estimatedDistance = nil
    }
    
    func formattedETA() -> String {
        guard let time = estimatedTime else { return "N/A" }
        let minutes = Int(time / 60)
        return "\(minutes) min"
    }
    
    func formattedDistance() -> String {
        guard let distance = estimatedDistance else { return "N/A" }
        return String(format: "%.1f km", distance / 1000)
    }
}

// MARK: - Location Accuracy Improvement

class AccurateLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var highAccuracyLocation: CLLocation?
    @Published var accuracy: CLLocationAccuracy = 0
    
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Update every 10 meters
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }
    
    func startHighAccuracyTracking() {
        locationManager.startUpdatingLocation()
    }
    
    func stopTracking() {
        locationManager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Only use locations with good horizontal accuracy (< 20 meters)
        if location.horizontalAccuracy > 0 && location.horizontalAccuracy < 20 {
            DispatchQueue.main.async {
                self.highAccuracyLocation = location
                self.accuracy = location.horizontalAccuracy
            }
        }
    }
}

// MARK: - Clustering Algorithm

struct ClusterManager {
    static func clusterLocations(_ locations: [ShuttleLocation], zoomLevel: Double) -> [(coordinate: CLLocationCoordinate2D, drivers: [ShuttleLocation])] {
        // If only 1 or 2 drivers, no clustering needed
        if locations.count <= 2 {
            return locations.map { (coordinate: $0.location.coordinate, drivers: [$0]) }
        }
        
        // Determine clustering distance based on zoom level
        let clusterDistance: CLLocationDistance = zoomLevel < 0.01 ? 100 : 500 // meters
        
        var clusters: [(coordinate: CLLocationCoordinate2D, drivers: [ShuttleLocation])] = []
        var remainingLocations = locations
        
        while !remainingLocations.isEmpty {
            let current = remainingLocations.removeFirst()
            var cluster = [current]
            
            // Find nearby drivers
            remainingLocations.removeAll { location in
                let distance = CLLocation(latitude: current.location.latitude, longitude: current.location.longitude)
                    .distance(from: CLLocation(latitude: location.location.latitude, longitude: location.location.longitude))
                
                if distance < clusterDistance {
                    cluster.append(location)
                    return true
                }
                return false
            }
            
            // Calculate cluster center
            let avgLat = cluster.map { $0.location.latitude }.reduce(0, +) / Double(cluster.count)
            let avgLon = cluster.map { $0.location.longitude }.reduce(0, +) / Double(cluster.count)
            
            clusters.append((coordinate: CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon), drivers: cluster))
        }
        
        return clusters
    }
}

// MARK: - Route History Manager

class RouteHistoryManager: ObservableObject {
    @Published var routeHistory: [CLLocationCoordinate2D] = []
    @Published var historyPolyline: MKPolyline?
    
    private let maxHistoryPoints = 100
    
    func addLocation(_ coordinate: CLLocationCoordinate2D) {
        routeHistory.append(coordinate)
        
        // Limit history size
        if routeHistory.count > maxHistoryPoints {
            routeHistory.removeFirst()
        }
        
        updatePolyline()
    }
    
    func updatePolyline() {
        guard routeHistory.count > 1 else { return }
        
        var coordinates = routeHistory
        let polyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)
        
        DispatchQueue.main.async {
            self.historyPolyline = polyline
        }
    }
    
    func clearHistory() {
        routeHistory.removeAll()
        historyPolyline = nil
    }
}

