import Foundation
import Combine
import SwiftUI

enum NetworkError: Error {
    case invalidURL
    case noData
    case decodingError
    case serverError(String)
    case rateLimitExceeded
    case imageLoadingError
}

class NetworkManager: ObservableObject {
    static let shared = NetworkManager()
    private let logger = CustomLogger.shared
    private var imageCache = NSCache<NSString, UIImage>()
    
    init() {
        imageCache.countLimit = 100 // Adjust cache size as needed
    }
    
    func searchPlaces(query: String, body: [String: Any]) async throws -> SearchResponse {
        let url = URL(string: "https://polomaps.com/api/search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw NetworkError.serverError("Invalid response from server")
            }
            
            // Log the raw JSON response
            if let jsonString = String(data: data, encoding: .utf8) {
                logger.info("Raw API response: \(jsonString)")
            }
            
            do {
                let jsonResponse = try JSONDecoder().decode(SearchResponse.self, from: data)
                // Log distances for debugging
                if let distance = jsonResponse.places?.first?.distanceObject?.distance {
                    logger.info("Place: \(jsonResponse.places?.first?.name ?? "Unknown"), Distance: \(distance)km")
                }
                return jsonResponse
            } catch {
                logger.error("Failed to decode API response: \(error.localizedDescription)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    logger.debug("Raw API response: \(jsonString)")
                }
                throw NetworkError.decodingError
            }
        } catch {
            logger.error("Network request failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    func getAirbnbPhotoUrl(place: Place) -> URL? {
        logger.info("Getting photo URL for place: \(place.googleMapsUri ?? "unknown")")
        
        guard let photos = place.photos, !photos.isEmpty else {
            logger.error("No photos available for place: \(place.googleMapsUri ?? "unknown")")
            return nil
        }
        
        let photoName = photos[0].name
        logger.info("Full photo name: \(photoName)")
        
        // Extract the place ID from the photo name
        let components = photoName.split(separator: "/").map(String.init)
        guard components.count >= 4,
              let placeId = components[safe: 1],
              let photoReference = components[safe: 3] else {
            logger.error("Could not extract IDs from photo name: \(photoName)")
            return nil
        }
        
        let urlString = "https://www.airbnb.nl/google_place_photo?photoreference=\(photoReference)&maxwidth=640&maxheight=640&id_type=ACP_ID&poi_id=t-g-\(placeId)"
        
        // Log the constructed URL
        logger.info("Constructed Airbnb URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            logger.error("Failed to create URL from string: \(urlString)")
            return nil
        }
        
        return url
    }
    
    func loadImage(for place: Place) async throws -> UIImage? {
        logger.info("Starting image load for place: \(place.googleMapsUri ?? "unknown")")
        
        guard let photoUrl = getAirbnbPhotoUrl(place: place) else {
            logger.error("Could not construct photo URL for place: \(place.googleMapsUri ?? "unknown")")
            return nil
        }
        
        logger.info("Loading image from URL: \(photoUrl.absoluteString)") // Log the URL being loaded
        
        // Check cache first
        let cacheKey = photoUrl.absoluteString as NSString
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            logger.info("Found cached image for place: \(place.googleMapsUri ?? "unknown")")
            return cachedImage
        }
        
        logger.info("Fetching image from URL: \(photoUrl.absoluteString)")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: photoUrl)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response type for image request")
                throw NetworkError.imageLoadingError
            }
            
            logger.info("Image response status code: \(httpResponse.statusCode)")
            
            guard (200...299).contains(httpResponse.statusCode) else {
                logger.error("Server error loading image: \(httpResponse.statusCode)")
                throw NetworkError.imageLoadingError
            }
            
            guard let image = UIImage(data: data) else {
                logger.error("Failed to create image from data")
                throw NetworkError.imageLoadingError
            }
            
            logger.info("Successfully loaded image for place: \(place.googleMapsUri ?? "unknown")")
            
            // Cache the loaded image
            imageCache.setObject(image, forKey: cacheKey)
            return image
            
        } catch {
            logger.error("Failed to load image: \(error.localizedDescription)")
            throw NetworkError.imageLoadingError
        }
    }
}

// Helper extension to safely access array elements
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// Assuming you have a logger instance in your NetworkManager
let logger = CustomLogger.shared

// Assuming you have a method to parse the JSON response
func parsePlaces(from data: Data) -> [Place]? {
    do {
        let decoder = JSONDecoder()
        let places = try decoder.decode([Place].self, from: data)
        
        // Log each place's distance
        for place in places {
            logger.info("Parsed distance: \(place.distanceObject?.description ?? "N/A") for place: \(place.name ?? "Unknown")")
        }
        
        return places
    } catch {
        logger.error("Failed to parse places: \(error.localizedDescription)")
        return nil
    }
}

// Assuming you have a function or method where you process each place
func processPlace(place: Place) {
    // Log the distance of the place
    if let distance = place.distanceObject {
        logger.info("Distance for place \(place.name ?? "Unknown"): \(distance.description)")
    } else {
        logger.info("Distance not available for place \(place.name ?? "Unknown")")
    }

    // Existing code to process the place
    // ...
}

