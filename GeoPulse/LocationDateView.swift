//
//  LocationDateView.swift
//  GeoPulse
//
//  Created by Aarush Pancholi on 10/4/25.
//


import SwiftUI
import MapKit

struct LocationDateView: View {
    @EnvironmentObject var app: AppState
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var searchText: String = ""
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 25.2048, longitude: 55.2708), // Dubai default
        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
    )
    @State private var pin: CLLocationCoordinate2D? = nil
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack(alignment: .top) {
                Map(position: $cameraPosition, interactionModes: [.pan, .zoom, .rotate]) {
                    if pin != nil {
                        Annotation(app.placename ?? "Selected", coordinate: pin!) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8).fill(.ultraThickMaterial)
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.red)
                                    .padding(6)
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                    let pt = value.location
                    if let coord = convertToCoordinate(from: pt) {
                        pin = coord
                        app.coordinate = coord
                        app.placename = "Custom Pin"
                    }
                })

                searchBar
                    .padding(.top, 10)
                    .padding(.horizontal)
            }
            .frame(maxHeight: .infinity)

            VStack(spacing: 12) {
                DatePicker("Date", selection: $app.selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .padding()
                    .background(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.yellow.opacity(0.25), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                HStack {
                    if pin != nil {
                        Text("\(app.placename ?? "Selected Location")")
                            .font(.callout)
                        Spacer()
                        Text("\(String(format: "%.4f, %.4f", pin!.latitude, pin!.longitude))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Tap the map to drop a pin.")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .padding(.horizontal, 4)

                NavigationLink {
                    ComfortProfileView()
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text("Choose Comfort Profile")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.yellow.opacity(0.25), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(pin == nil)
            }
            .padding()
            .background(.background)
        }
        .navigationTitle("Pick Place & Date")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let coord = app.coordinate {
                pin = coord
                region.center = coord
            }
        }
    }

    // MARK: - UI Bits

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.title3)
                .foregroundStyle(.yellow)
            Text("Drop a pin or search")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("Search place (e.g., Burj Park)", text: $searchText)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .onSubmit { geocodeSearch() }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.thinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 6, y: 3)
    }

    // MARK: - Helpers

    private func geocodeSearch() {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            guard let item = response?.mapItems.first else { return }
            let coord = item.placemark.coordinate
            pin = coord
            app.coordinate = coord
            app.placename = item.name
            withAnimation {
                let newRegion = MKCoordinateRegion(center: coord,
                                                   span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25))
                cameraPosition = .region(newRegion)
                region = newRegion
            }
            isSearchFocused = false
        }
    }

    // Converts a screen point to map coordinate (best-effort; Map does not expose direct API, so we nudge camera)
    private func convertToCoordinate(from _: CGPoint) -> CLLocationCoordinate2D? {
        // As a simple stand-in, use tracked region center:
        return region.center
    }
}

#Preview {
    NavigationStack {
        LocationDateView()
            .environmentObject(AppState())
    }
}
