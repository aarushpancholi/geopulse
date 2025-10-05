import SwiftUI
import MapKit
import Combine

// MARK: - Shared Models & App State (kept here so you only need 4 files)

struct ComfortPreset: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let emoji: String
    let description: String
    // Internal thresholds (you can later store these in Firestore)
    let maxHotC: Double?      // e.g. 30°C means "too hot if > 30"
    let minColdC: Double?     // e.g. 5°C  means "too cold if < 5"
    let maxRainMM: Double?    // e.g. 10mm means "too wet if >= 10"
    let maxWindKPH: Double?   // e.g. 25kph means "too windy if >= 25"
}

struct OddsResult: Identifiable {
    let id = UUID()
    let label: String
    let valuePercent: Double  // 0..100
    let note: String
    let systemIcon: String
}

struct WeatherSummary {
    let avgHighC: Double
    let avgLowC: Double
    let avgPrecipMM: Double
    let avgWindKPH: Double
}

final class AppState: ObservableObject {
    @Published var coordinate: CLLocationCoordinate2D? = nil
    @Published var placename: String? = nil
    @Published var selectedDate: Date = Date()
    @Published var selectedPreset: ComfortPreset? = nil
    @Published var customMaxHot: Double? = nil
    @Published var customMinCold: Double? = nil
    @Published var customMaxRain: Double? = nil
    @Published var customMaxWind: Double? = nil

    @Published var results: [OddsResult] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    @Published var weatherSummary: WeatherSummary? = nil

    // For demo presets
    let presets: [ComfortPreset] = [
        .init(name: "Warm & Sunny", emoji: "☀️",
              description: "Prefer heat, avoid rain/wind.",
              maxHotC: 35, minColdC: 15, maxRainMM: 5,  maxWindKPH: 25),
        .init(name: "Mild & Pleasant", emoji: "🙂",
              description: "Comfortable temps, little rain.",
              maxHotC: 30, minColdC: 10, maxRainMM: 8,  maxWindKPH: 30),
        .init(name: "Cool & Breezy", emoji: "🍃",
              description: "Cooler temps, OK with wind.",
              maxHotC: 25, minColdC: 5,  maxRainMM: 10, maxWindKPH: 35)
    ]
}

// MARK: - Mock NASA odds service (swap with Firebase Cloud Function later)
enum NASAOddsService {
    /// Simulates odds using deterministic noise so results feel realistic.
    static func computeOdds(
        coord: CLLocationCoordinate2D,
        date: Date,
        maxHotC: Double?,
        minColdC: Double?,
        maxRainMM: Double?,
        maxWindKPH: Double?
    ) async throws -> [OddsResult] {
        // In production: call your Firebase Cloud Function that:
        // 1) hits NASA POWER for daily climatology at lat/lon around day-of-year
        // 2) calculates exceedance probabilities for thresholds
        // 3) returns percentages

        // Demo math: stable pseudo-randomness based on lat/lon/dayOfYear
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 180
        func seed(_ base: Double) -> Double {
            let s = sin(coord.latitude * 3.7 + coord.longitude * 1.9 + Double(day) * 0.07 + base)
            return (s + 1) / 2 // 0..1
        }

        func clamp(_ v: Double) -> Double { max(0, min(100, v)) }

        // If a threshold isn't set, we skip that metric
        var arr: [OddsResult] = []

        if let hot = maxHotC {
            let pct = 100 * pow(seed(1.0), (hot / 10.0))
            arr.append(.init(label: "Too hot > \(Int(hot)) °C",
                             valuePercent: clamp(pct),
                             note: "Historical odds of hotter-than-threshold.",
                             systemIcon: "thermometer.sun"))
        }
        if let cold = minColdC {
            let pct = 100 * pow(seed(2.0), (15.0 / max(cold, 1))) // lower cold threshold ⇒ higher odds
            arr.append(.init(label: "Too cold < \(Int(cold)) °C",
                             valuePercent: clamp(pct),
                             note: "Historical odds of colder-than-threshold.",
                             systemIcon: "thermometer.snowflake"))
        }
        if let rain = maxRainMM {
            let pct = 100 * pow(seed(3.0), (8.0 / max(rain, 0.5)))
            arr.append(.init(label: "Rain ≥ \(Int(rain)) mm",
                             valuePercent: clamp(pct),
                             note: "Daily precipitation exceedance odds.",
                             systemIcon: "cloud.rain"))
        }
        if let wind = maxWindKPH {
            let pct = 100 * pow(seed(4.0), (28.0 / max(wind, 1)))
            arr.append(.init(label: "Wind ≥ \(Int(wind)) km/h",
                             valuePercent: clamp(pct),
                             note: "Daily wind exceedance odds.",
                             systemIcon: "wind"))
        }
        return arr
    }
}

// MARK: - Welcome / Onboarding

struct WelcomeOnboardingView: View {
    @StateObject private var app = AppState()
    @State private var isAnimating = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                RadialGradient(colors: [Color.yellow.opacity(0.35), Color.clear], center: .topLeading, startRadius: 60, endRadius: 600)
                    .blendMode(.plusLighter)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Text("GeoPulse")
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .foregroundStyle(.yellow)
                            .opacity(isAnimating ? 1 : 0)
                            .offset(y: isAnimating ? 0 : 10)
                            .animation(.spring(duration: 0.9, bounce: 0.35), value: isAnimating)

                        Text("Odds of good weather, anywhere.\nPowered by NASA data.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.85))
                            .font(.title3.weight(.medium))
                            .opacity(isAnimating ? 1 : 0)
                            .offset(y: isAnimating ? 0 : 8)
                            .animation(.spring(duration: 1.0, bounce: 0.3).delay(0.05), value: isAnimating)
                    }
                    .padding(.top, 40)

                    EarthGLBView(rotationDuration: 40, allowsCameraControl: false)
                        .frame(height: 260)
                        .glassCard(cornerRadius: 20)
                        .padding(.horizontal)
                        .opacity(isAnimating ? 1 : 0)
                        .offset(y: isAnimating ? 0 : 10)
                        .animation(.spring(duration: 1.0, bounce: 0.28).delay(0.08), value: isAnimating)

                    VStack(spacing: 14) {
                        FeatureRow(icon: "mappin.and.ellipse", title: "Pick a spot", subtitle: "Drop a pin or search any place.")
                        FeatureRow(icon: "calendar", title: "Pick a date", subtitle: "Choose any day of the year.")
                        FeatureRow(icon: "slider.horizontal.3", title: "Pick comfort", subtitle: "Use a simple preset (or tweak).")
                        FeatureRow(icon: "chart.bar", title: "See the odds", subtitle: "Clear, color-coded percentages.")
                    }
                    .padding()
                    .background(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.yellow.opacity(0.25), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
                    .opacity(isAnimating ? 1 : 0)
                    .offset(y: isAnimating ? 0 : 12)
                    .animation(.spring(duration: 1.0, bounce: 0.28).delay(0.1), value: isAnimating)
                    .padding(.horizontal)

                    NavigationLink {
                        LocationDateView()
                            .environmentObject(app)
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Get Started")
                                .fontWeight(.semibold)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                        )
                        .foregroundStyle(.yellow)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
                        .opacity(isAnimating ? 1 : 0)
                        .offset(y: isAnimating ? 0 : 12)
                        .animation(.spring(duration: 1.1, bounce: 0.25).delay(0.15), value: isAnimating)
                        .padding(.horizontal)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onAppear {
                isAnimating = true
            }
        }
        .environmentObject(app)
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.yellow.opacity(0.18))
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.yellow)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Preview
#Preview {
    WelcomeOnboardingView()
}
