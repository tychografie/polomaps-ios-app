import Foundation

struct Place: Identifiable, Codable {
    struct DisplayName: Codable {
        let languageCode: String?
        let text: String?
    }
    
    struct Location: Codable {
        let latitude: Double?
        let longitude: Double?
    }
    
    struct Distance: Codable {
        let distance: Double
        
        var description: String {
            return formatDistance(distance)
        }
        
        private func formatDistance(_ dist: Double) -> String {
            if dist < 1 {
                return "\(Int(dist * 1000))m"
            } else {
                return String(format: "%.1fkm", dist)
            }
        }
    }

    
    struct Photo: Codable {
        let name: String
        let widthPx: Int?
        let heightPx: Int?
        let authorAttributions: [AuthorAttribution]?
    }
    
    struct AuthorAttribution: Codable {
        let displayName: String?
        let uri: String?
        let photoUri: String?
    }

    let id: String  // This will be extracted from googleMapsUri
    let displayName: DisplayName?
    let googleMapsUri: String?
    let rating: Double?
    let userRatingCount: Int?
    let location: Location?
    private let distance: Double?
    var distanceObject: Distance? {
        distance.flatMap(Distance.init(distance:))
    }
    let name: String?
    let photos: [Photo]?
    
    private enum CodingKeys: String, CodingKey {
        case displayName, googleMapsUri, rating, userRatingCount, location, distance, name, photos
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.displayName = try? container.decode(DisplayName.self, forKey: .displayName)
        self.googleMapsUri = try? container.decode(String.self, forKey: .googleMapsUri)
        self.rating = try? container.decode(Double.self, forKey: .rating)
        self.userRatingCount = try? container.decode(Int.self, forKey: .userRatingCount)
        self.location = try? container.decode(Location.self, forKey: .location)
        self.distance = try? container.decode(Double.self, forKey: .distance)
        self.name = try? container.decode(String.self, forKey: .name)
        self.photos = try? container.decode([Photo].self, forKey: .photos)
        
        // Extract the ID from googleMapsUri
        // Format: https://maps.google.com/?cid=12345
        if let uri = self.googleMapsUri,
           let cidIndex = uri.range(of: "cid=")?.upperBound {
            self.id = String(uri[cidIndex...])
        } else {
            self.id = UUID().uuidString
        }
    }
}

struct AIResponse: Codable {
    let originalQuery: String?
    let aiQuery: String?
    let aiEmoji: String?
    let aiType: String?
    let modeisLatLong: Bool?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.originalQuery = try? container.decode(String.self, forKey: .originalQuery)
        self.aiQuery = try? container.decode(String.self, forKey: .aiQuery)
        self.aiEmoji = try? container.decode(String.self, forKey: .aiEmoji)
        self.aiType = try? container.decode(String.self, forKey: .aiType)
        self.modeisLatLong = try? container.decode(Bool.self, forKey: .modeisLatLong)
    }
}

struct SearchResponse: Codable {
    let places: [Place]?
    let aiResponse: AIResponse?
    let searchId: String?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.places = try? container.decode([Place].self, forKey: .places)
        self.aiResponse = try? container.decode(AIResponse.self, forKey: .aiResponse)
        self.searchId = try? container.decode(String.self, forKey: .searchId)
    }
}

extension Place: Equatable {
    static func == (lhs: Place, rhs: Place) -> Bool {
        return lhs.googleMapsUri == rhs.googleMapsUri
    }
}
