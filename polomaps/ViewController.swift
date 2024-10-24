import SwiftUI
import CoreLocation
import Network
import MapKit


struct MainScreenView: View {
    @State private var selectedTab = 0
    @Environment(\.colorScheme) private var colorScheme
    @State private var query: String = ""
    @State private var locationEnabled: Bool = false
    @State private var radius: Int = 500
    @State private var results: [Place] = []
    @State private var isLoading: Bool = false
    @State private var appearAnimation: Bool = false
    @State private var keyboardHeight: CGFloat = 0
    @StateObject private var locationManager = LocationManager()
    @StateObject private var networkManager = NetworkManager()
    @StateObject private var connectivityManager = NetworkConnectivityManager()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 52.3676, longitude: 4.9041),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var showingMap: Bool = false
    
    @State private var buttonText: String = "Search"
    @State private var errorMessage: String = ""
    @State private var showWelcomeSheet: Bool = true
    @State private var animationProgress: CGFloat = 0
    @State private var showLocationPermissionAlert: Bool = false
    @State private var showOfflineAlert: Bool = false
    
    @State private var currentPlaceholderIndex: Int = 0
    @State private var placeholderOpacity: Double = 1.0
    
    @FocusState private var isTextFieldFocused: Bool
    
    @State private var currentPage = 1
    @State private var isLoadingMoreResults = false
    @State private var hasMoreResults = true
    @State private var keyboardVisible: Bool = false
    @State private var searchAttempts: Int = 0
    
    private let maxSearchAttemptsPerMinute = 10
    private let searchCooldownPeriod: TimeInterval = 60
    private let minimumQueryLength = 3
    
    let placeholders = Placeholders.searchQueries
    private let logger = CustomLogger.shared
    
    var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color(hex: "#FBEED2")
    }
    
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                backgroundColor.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if !connectivityManager.isConnected {
                        offlineView
                    } else if isLoading {
                        loadingView
                    } else if results.isEmpty {
                        emptyStateView
                    } else {
                        ZStack(alignment: .top) {
                            // Content
                            if selectedTab == 0 {
                                ScrollView {
                                    VStack(spacing: 10) {
                                        // Add padding at top to account for fixed segment control
                                        Color.clear.frame(height: 60)
                                        resultsView
                                    }
                                    .padding(.bottom, locationEnabled ? 120 : 100)
                                }
                                .transition(.opacity)
                            } else {
                                MapViewWrapper(places: results, region: $region)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .edgesIgnoringSafeArea(.all)
                                    .transition(.opacity)
                            }
                            
                            // Fixed segment control at top
                            VStack {
                                HStack(spacing: 4) {
                                    SegmentedButton(
                                        icon: "list.bullet",
                                        title: "List",
                                        isSelected: selectedTab == 0,
                                        action: { selectedTab = 0 }
                                    )
                                    
                                    SegmentedButton(
                                        icon: "map",
                                        title: "Map",
                                        isSelected: selectedTab == 1,
                                        action: { selectedTab = 1 }
                                    )
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : .white)
                                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                )
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                            }
                        }
                        .animation(.easeInOut, value: selectedTab)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .blur(radius: keyboardVisible ? 3 : 0)

                // Only show gradient view in list tab
                if selectedTab == 0 {
                    gradientView
                        .frame(maxWidth: .infinity)
                        .offset(y: 50)
                        .padding(.bottom, 0)
                }
                
                // Hero section with shadow
                VStack(spacing: 0) {
                    heroSection
                        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 4)
                }
                .frame(height: locationEnabled ? 120 : 100)
                .offset(y: keyboardVisible ? -keyboardHeight + geometry.safeAreaInsets.bottom - (locationEnabled ? 20 : 0) : 0)
            }
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            setupApp()
            print("MainScreenView appeared")
        }
        .onChange(of: results) { _, newResults in
            print("Results updated: \(newResults.count) places")
            if let firstPlace = newResults.first,
               let lat = firstPlace.location?.latitude,
               let lon = firstPlace.location?.longitude {
                print("Updating region to center: \(lat), \(lon)")
                withAnimation {
                    region = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    )
                }
            }
        }
        .sheet(isPresented: $showWelcomeSheet) {
            WelcomeSheetView(isPresented: $showWelcomeSheet)
                .presentationDetents([.height(UIScreen.main.bounds.height * 0.65)])
        }
        .alert("Location Access Required", isPresented: $showLocationPermissionAlert) {
            Button("Open Settings", role: .none) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable location services in Settings to find places near you.")
        }
        .alert("No Internet Connection", isPresented: $showOfflineAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please check your internet connection and try again.")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let keyboardFrame: NSValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
                let keyboardRectangle = keyboardFrame.cgRectValue
                keyboardHeight = keyboardRectangle.height
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardVisible = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardVisible = false
                keyboardHeight = 0
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Places Search Screen")
    }



    var offlineView: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("No Internet Connection")
                .font(.custom("Belanosima-Regular", size: 20))
            
            Text("Please check your connection and try again")
                .font(.custom("Belanosima-Regular", size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                connectivityManager.checkConnectivity()
            }) {
                Text("Retry")
                    .font(.custom("Belanosima-Regular", size: 16))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(8)
            }
        }
        .padding()
    }
    
    var emptyStateView: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 12) {
                    Image("discover")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .foregroundColor(colorScheme == .dark ? .white : .secondary)
                    
                    Text("Go on then, discover the world!")
                        .font(.custom("Belanosima-Regular", size: 18))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(width: geometry.size.width * 0.8)
                .padding()
                .cornerRadius(8)
                
                Spacer()
            }
            .frame(width: geometry.size.width)
        }
    }
    
    var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
                .padding()
            Text("Searching for local gems...")
                .font(.custom("Belanosima-Regular", size: 18))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor)
        .transition(.opacity)
    }
    
    var resultsView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(results, id: \.googleMapsUri) { place in
                    PlaceView(place: place)
                        .opacity(animationProgress > 0 ? 1 : 0)
                        .offset(y: animationProgress > 0 ? 0 : 50)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0.5), value: animationProgress)
                        .onTapGesture {
                            if keyboardVisible {
                                dismissKeyboard()
                            } else {
                                openGoogleMaps(for: place)
                            }
                        }
                }
                
                if !results.isEmpty && hasMoreResults {
                    GeometryReader { geometry in
                        Color.clear.preference(key: ScrollOffsetPreferenceKey.self, value: geometry.frame(in: .named("scroll")).maxY)
                    }
                    .frame(height: 20)
                    .onAppear {
                        loadMoreResults()
                    }
                }
                
                if isLoadingMoreResults {
                    ProgressView()
                        .padding()
                }
            }
            .coordinateSpace(name: "scroll")
            .padding(.horizontal, 20)
        }
    }
    
    var heroSection: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Button(action: {
                        if locationEnabled {
                            locationEnabled = false
                            locationManager.location = nil
                        } else {
                            Task {
                                await locationManager.requestLocation()
                            }
                            locationEnabled = true
                        }
                    }) {
                        Image(systemName: locationEnabled ? "location.fill" : "location")
                            .foregroundColor(locationEnabled ? .blue : .gray)
                    }
                    .frame(width: 44, height: 44)
                    .padding(.leading, 8)
                    
                    TextField(placeholders[currentPlaceholderIndex], text: $query)
                        .focused($isTextFieldFocused)
                        .padding(.leading, 10)
                        .padding(.trailing, 12)
                        .font(.custom("Belanosima-Regular", size: 18))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity)
                        .keyboardType(.default)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit {
                            sendQuery(query: query)
                        }
                        .opacity(query.isEmpty ? placeholderOpacity : 1)
                }
                .frame(height: 60)
                
                if locationEnabled, let locationDescription = locationManager.locationDescription {
                    Divider()
                        .background(Color.gray.opacity(0.5))
                        .padding(.horizontal, 10)
                    
                    HStack(spacing: 0) {
                        Picker("Distance", selection: $radius) {
                            Text("250m").tag(250)
                            Text("500m").tag(500)
                            Text("1km").tag(1000)
                            Text("5km").tag(5000)
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 90)
                        
                        Text("from \(locationDescription)")
                            .font(.custom("Belanosima-Regular", size: 16))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(height: 60)
                    .padding(.leading, 5)
                    .padding(.trailing, 24)
                }
            }
            .background(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemBackground))
            .cornerRadius(8)
            .animation(.easeInOut, value: locationEnabled)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
    
    private func setupApp() {
        connectivityManager.startMonitoring()
        withAnimation {
            appearAnimation = true
        }
        startPlaceholderAnimation()
    }
    
    func startPlaceholderAnimation() {
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                placeholderOpacity = 0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                currentPlaceholderIndex = (currentPlaceholderIndex + 1) % placeholders.count
                withAnimation(.easeInOut(duration: 0.5)) {
                    placeholderOpacity = 1
                }
            }
        }
    }
    
    func sendQuery(query: String) {
        guard searchAttempts < maxSearchAttemptsPerMinute else {
            showError("Too many searches. Please wait a moment.")
            return
        }
        
        guard connectivityManager.isConnected else {
            showOfflineAlert = true
            return
        }
        
        let sanitizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitizedQuery.count >= minimumQueryLength else {
            showError("Please enter at least \(minimumQueryLength) characters")
            return
        }
        
        guard !sanitizedQuery.isEmpty else {
            showError("Please enter a valid search term")
            return
        }
        
        isLoading = true
        errorMessage = ""
        results = []
        animationProgress = 0
        searchAttempts += 1
        
        DispatchQueue.main.asyncAfter(deadline: .now() + searchCooldownPeriod) {
            searchAttempts -= 1
        }
        
        var body: [String: Any] = ["query": sanitizedQuery]
        
        if locationEnabled {
            guard let location = locationManager.location else {
                showLocationPermissionAlert = true
                isLoading = false
                return
            }
            
            body["latitude"] = location.coordinate.latitude
            body["longitude"] = location.coordinate.longitude
            if let country = locationManager.country {
                body["country"] = country
            }
            body["radius"] = radius
        }
        
        logger.info("Sending search query: \(sanitizedQuery)")
        
        Task {
            do {
                let searchResponse = try await networkManager.searchPlaces(query: sanitizedQuery, body: body)
                await MainActor.run {
                    handleSearchResponse(searchResponse)
                }
            } catch NetworkError.rateLimitExceeded {
                await MainActor.run {
                    showError("Please wait a moment before trying again")
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }
    
    func handleSearchResponse(_ response: SearchResponse) {
            if let places = response.places, !places.isEmpty {
                logger.info("Received \(places.count) places from API")
                print("First place details:")
                if let firstPlace = places.first {
                    print("  Name: \(firstPlace.displayName?.text ?? firstPlace.name ?? "Unknown")")
                    print("  Location: \(firstPlace.location?.latitude ?? 0), \(firstPlace.location?.longitude ?? 0)")
                }
                
                self.results = places.filter { $0.rating ?? 0 >= 3.0 }
                self.hasMoreResults = places.count >= 20
                self.buttonText = "Search"
                
                // Debug the filtered results
                print("Filtered to \(self.results.count) places with rating >= 3.0")
            } else {
                logger.info("No places found in API response")
                self.showError("No matching places found. Try different keywords.")
            }
            self.isLoading = false
            self.animateResults()
        }
    
    func handleError(_ error: Error) {
        let errorMessage: String
        switch error {
        case NetworkError.invalidURL:
            errorMessage = "Unable to process request. Please try again."
        case NetworkError.noData:
            errorMessage = "No results found. Please try different keywords."
        case NetworkError.decodingError:
            errorMessage = "Unable to process results. Please try again."
        case NetworkError.serverError(let message):
            errorMessage = "Unable to complete search: \(message)"
        case NetworkError.rateLimitExceeded:
            errorMessage = "Too many searches. Please wait a moment."
        case is URLError:
            errorMessage = "Connection problem. Please check your internet."
        default:
            errorMessage = "Something went wrong. Please try again."
        }
        logger.error("Search error: \(errorMessage)")
        self.showError(errorMessage)
    }
    
    func showError(_ message: String) {
        self.errorMessage = message
        self.buttonText = "Try again?"
        self.isLoading = false
    }
    
    func openGoogleMaps(for place: Place) {
        if let urlString = place.googleMapsUri, let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    func animateResults() {
        animationProgress = 0
        withAnimation(.easeInOut(duration: 0.5)) {
            animationProgress = 1
        }
    }
    
    func loadMoreResults() {
        guard !isLoadingMoreResults && hasMoreResults else { return }
        isLoadingMoreResults = true
        
        let nextPage = currentPage + 1
        
        Task {
            do {
                var body: [String: Any] = ["query": query, "page": nextPage]
                
                if locationEnabled, let location = locationManager.location {
                    body["latitude"] = location.coordinate.latitude
                    body["longitude"] = location.coordinate.longitude
                    body["radius"] = radius
                }
                
                let response = try await networkManager.searchPlaces(query: query, body: body)
                
                await MainActor.run {
                    if let newPlaces = response.places, !newPlaces.isEmpty {
                        let filteredPlaces = newPlaces.filter { $0.rating ?? 0 >= 3.0 }
                        results.append(contentsOf: filteredPlaces)
                        currentPage = nextPage
                        hasMoreResults = newPlaces.count >= 20
                    } else {
                        hasMoreResults = false
                    }
                    isLoadingMoreResults = false
                }
            } catch {
                await MainActor.run {
                    isLoadingMoreResults = false
                    hasMoreResults = false
                    logger.error("Error loading more results: \(error)")
                }
            }
        }
    }
    
    var gradientView: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                colorScheme == .dark ? Color.black.opacity(0) : Color(hex: "#FBEED2").opacity(0),
                colorScheme == .dark ? Color.black.opacity(1) : Color(hex: "#FBEED2").opacity(1)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .blur(radius: 10)
        .cornerRadius(10)
        .padding(.horizontal, 20)
        .frame(height: 130)
    }
}


struct SegmentedButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                    .font(.custom("Belanosima-Regular", size: 18))
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct WelcomeSheetView: View {
    @Binding var isPresented: Bool
    @State private var currentImageIndex: Int
    
    let images = ["palermo", "tokyo", "porto", "paris", "oaxaca"]
    
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        self._currentImageIndex = State(initialValue: Int.random(in: 0..<5))
    }
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                ForEach(0..<images.count, id: \.self) { index in
                    Image(images[index])
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 200)
                        .opacity(currentImageIndex == index ? 1 : 0)
                        .animation(.easeInOut(duration: 0.5), value: currentImageIndex)
                }
            }
            .frame(height: 200)
            .clipped()
            .onAppear {
                Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                    withAnimation {
                        currentImageIndex = (currentImageIndex + 1) % images.count
                    }
                }
            }
            
            Text("Welcome to Polomaps")
                .font(.custom("Belanosima-Regular", size: 24))
            
            Text("Discover the best local spots around you")
                .font(.custom("Belanosima-Regular", size: 18))
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 10) {
                TipView(text: "Turn on location to find nearby places")
                TipView(text: "Search by neighbourhood for better spots")
                TipView(text: "Tap on a result to view it on Google Maps")
            }
            .padding()
            
            Button(action: {
                isPresented = false
            }) {
                Text("Get Started")
                    .font(.custom("Belanosima-Regular", size: 18))
                    .foregroundColor(Color(hex: "#440C4C"))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(hex: "#E5B363"))
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}


struct MapViewWrapper: View {
    let places: [Place]
    @Binding var region: MKCoordinateRegion
    @State private var selectedPlace: Place?
    @State private var placeImages: [String: UIImage] = [:]
    @State private var isExpanded: Bool = false
    private let logger = CustomLogger.shared
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        GeometryReader { geometry in
            Map(coordinateRegion: $region,
                showsUserLocation: true,
                annotationItems: places) { place in
                    MapAnnotation(
                        coordinate: CLLocationCoordinate2D(
                            latitude: place.location?.latitude ?? 0,
                            longitude: place.location?.longitude ?? 0
                        )
                    ) {
                        VStack(spacing: 4) {
                            ZStack {
                                if let image = placeImages[place.id] {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(
                                            width: selectedPlace?.id == place.id && isExpanded ? 66 : 44,
                                            height: selectedPlace?.id == place.id && isExpanded ? 66 : 44
                                        )
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 3)
                                        )
                                        .shadow(radius: 3)
                                        .animation(.spring(response: 0.3), value: selectedPlace?.id == place.id && isExpanded)
                                } else {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(
                                            width: selectedPlace?.id == place.id && isExpanded ? 66 : 44,
                                            height: selectedPlace?.id == place.id && isExpanded ? 66 : 44
                                        )
                                        .overlay(
                                            Image(systemName: "photo")
                                                .foregroundColor(.white)
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 3)
                                        )
                                        .shadow(radius: 3)
                                        .animation(.spring(response: 0.3), value: selectedPlace?.id == place.id && isExpanded)
                                        .onAppear {
                                            loadImage(for: place)
                                        }
                                }
                                
                                // Rating badge
                                if let rating = place.rating {
                                    HStack(spacing: 1) {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 8))
                                        Text(String(format: "%.1f", rating))
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(8)
                                    .offset(x: 16, y: -16)
                                }
                            }
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if selectedPlace?.id == place.id {
                                        isExpanded.toggle()
                                    } else {
                                        selectedPlace = place
                                        isExpanded = true
                                    }
                                }
                            }
                            
                            if selectedPlace?.id == place.id {
                                VStack(spacing: 2) {
                                    Text(place.displayName?.text ?? place.name ?? "Unknown")
                                        .font(.custom("Belanosima-Regular", size: 14))
                                        .foregroundColor(.primary)
                                        .onTapGesture {
                                            if let urlString = place.googleMapsUri,
                                               let url = URL(string: urlString) {
                                                UIApplication.shared.open(url)
                                            }
                                        }
                                    if let distance = place.distanceObject?.description {
                                        Text(distance)
                                            .font(.custom("Belanosima-Regular", size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(colorScheme == .dark ? Color(hex: "#2C2C2E") : .white)
                                        .shadow(radius: 3)
                                )
                                .transition(.opacity)
                            }
                        }
                        .zIndex(selectedPlace?.id == place.id ? 1 : 0)
                    }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            logMapDetails()
            updateMapRegion()
        }
        .onChange(of: places.count) { newCount in
            logMapDetails()
            updateMapRegion()
        }
    }
    
    private func loadImage(for place: Place) {
        Task {
            do {
                if let image = try await NetworkManager.shared.loadImage(for: place) {
                    await MainActor.run {
                        placeImages[place.id] = image
                    }
                }
            } catch {
                logger.error("Error loading image for map pin: \(error.localizedDescription)")
            }
        }
    }
    
    private func logMapDetails() {
        print("MapView configuration:")
        print("Number of places: \(places.count)")
        print("Region center: \(region.center.latitude), \(region.center.longitude)")
        print("Region span: \(region.span.latitudeDelta), \(region.span.longitudeDelta)")
        
        for (index, place) in places.enumerated() {
            if let lat = place.location?.latitude,
               let lon = place.location?.longitude {
                print("Place \(index): \(place.displayName?.text ?? place.name ?? "Unknown") at (\(lat), \(lon))")
            }
        }
    }
    
    private func updateMapRegion() {
        guard !places.isEmpty else {
            print("No places to update region")
            return
        }
        
        let coordinates = places.compactMap { place -> CLLocationCoordinate2D? in
            guard let lat = place.location?.latitude,
                  let lon = place.location?.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        
        guard !coordinates.isEmpty else {
            print("No valid coordinates found")
            return
        }
        
        let minLat = coordinates.map(\.latitude).min() ?? 0
        let maxLat = coordinates.map(\.latitude).max() ?? 0
        let minLon = coordinates.map(\.longitude).min() ?? 0
        let maxLon = coordinates.map(\.longitude).max() ?? 0
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.02),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.02)
        )
        
        print("Updating region to center: \(center.latitude), \(center.longitude)")
        print("With span: \(span.latitudeDelta), \(span.longitudeDelta)")
        
        DispatchQueue.main.async {
            withAnimation {
                region = MKCoordinateRegion(center: center, span: span)
            }
        }
    }
}

extension Place {
    func debugPrint() {
        print("""
        Place Debug Info:
        - ID: \(id)
        - Name: \(displayName?.text ?? name ?? "Unknown")
        - Location: \(location?.latitude ?? 0), \(location?.longitude ?? 0)
        - Rating: \(rating ?? 0)
        - Has Maps URI: \(googleMapsUri != nil)
        """)
    }
}
struct TipView: View {
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(text)
                .font(.custom("Belanosima-Regular", size: 16))
        }
    }
}

struct AsyncImageView: View {
    let place: Place
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var hasError = false
    private let logger = CustomLogger.shared
    
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(
                        .rect(
                            topLeadingRadius: 8,
                            bottomLeadingRadius: 8
                        )
                    )
            } else if isLoading {
                ProgressView()
                    .frame(width: 80, height: 80)
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
                    .foregroundColor(.gray)
                    .frame(width: 80, height: 80)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(
                        .rect(
                            topLeadingRadius: 8,
                            bottomLeadingRadius: 8
                        )
                    )
            }
        }
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        logger.info("Starting image load in AsyncImageView for place: \(place.id)")
        do {
            isLoading = true
            if let loadedImage = try await NetworkManager.shared.loadImage(for: place) {
                logger.info("Successfully loaded and set image for place: \(place.id)")
                image = loadedImage
            } else {
                logger.error("No image returned for place: \(place.id)")
                hasError = true
            }
        } catch {
            logger.error("Error loading image for place \(place.id): \(error.localizedDescription)")
            hasError = true
        }
        isLoading = false
    }
}


struct PlaceView: View {
    let place: Place
    @Environment(\.colorScheme) private var colorScheme
    
    
    var body: some View {
        HStack(spacing: 12) {
            AsyncImageView(place: place)
                .frame(width: 80, height: 80)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(place.displayName?.text ?? place.name ?? "")
                    .font(.custom("Belanosima-Regular", size: 18))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                
                HStack(spacing: 8) {
                    if let rating = place.rating {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", rating))
                                .font(.custom("Belanosima-Regular", size: 16))
                                .foregroundColor(.primary)
                        }
                    }
                    
                    if let distance = place.distanceObject?.description {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(distance)
                            .font(.custom("Belanosima-Regular", size: 16))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(colorScheme == .dark ? Color(hex: "#2C2C2E") : Color.white)
        .cornerRadius(8)
    }
    
    private func formatDistance(_ distance: Double) -> String {
        if distance < 1 {
            return "\(Int(distance * 1000))m"
        } else {
            return String(format: "%.1fkm", distance)
        }
    }
}


extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct MainScreenView_Previews: PreviewProvider {
    static var previews: some View {
        MainScreenView()
    }
}


class NetworkConnectivityManager: ObservableObject {
    @Published var isConnected = true
    private let monitor = NWPathMonitor()
    
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor.start(queue: queue)
    }
    
    func checkConnectivity() {
        isConnected = monitor.currentPath.status == .satisfied
    }
    
    deinit {
        monitor.cancel()
    }
}






