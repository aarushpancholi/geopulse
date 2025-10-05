import SwiftUI
import Charts
import MapKit

struct ResultsView: View {
    @EnvironmentObject var app: AppState
    @State private var localError: String? = nil
    @State private var showShare = false
    private struct ExportItem: Identifiable { let id = UUID(); let url: URL }
    @State private var exportItem: ExportItem? = nil

    var body: some View {
        ZStack {
            // Soft colorful backdrop for a glassy feel
            RadialGradient(colors: [
                Color.yellow.opacity(0.22),
                Color.orange.opacity(0.18),
                Color.yellow.opacity(0.12),
                Color.clear
            ], center: .topLeading, startRadius: 80, endRadius: 600)
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard

                    weatherSummaryCard

                    if app.coordinate == nil {
                        locationPromptCard
                    }

                    if app.isLoading {
                        ProgressView("Crunching NASA data…")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.thinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(.yellow.opacity(0.25), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                    }

                    if let e = app.errorMessage ?? localError {
                        errorCard(text: e)
                    }

                    if !app.results.isEmpty {
                        chartCard
                        breakdownList
                        explainerCard
                        tipsCard
                    }

                    actionRow
                }
                .padding()
            }
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .task { await tryLoadIfReady() }
        .onChange(of: app.coordinate?.latitude) { _ in
            Task { await tryLoadIfReady() }
        }
        .onChange(of: app.coordinate?.longitude) { _ in
            Task { await tryLoadIfReady() }
        }
        .sheet(item: $exportItem) { item in
            ShareSheet(activityItems: [item.url])
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let coord = app.coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(center: coord,
                                                                   span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)))) {
                        Annotation("", coordinate: coord) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.red)
                        }
                    }
                    .mapStyle(.standard)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(app.placename ?? "Selected Location")
                        .font(.headline)
                    Text(dateString(app.selectedDate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let p = chosenPresetName {
                        Label(p, systemImage: "slider.horizontal.3")
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Label("Custom thresholds", systemImage: "slider.horizontal.3")
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(.thinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.yellow.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var weatherSummaryCard: some View {
        Group {
            if let s = app.weatherSummary {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today's climatology snapshot")
                        .font(.headline)
                    HStack(spacing: 16) {
                        Label("High: \(Int(round(s.avgHighC)))°C", systemImage: "thermometer.sun")
                        Label("Low: \(Int(round(s.avgLowC)))°C", systemImage: "thermometer.snowflake")
                    }
                    .font(.subheadline)
                    HStack(spacing: 16) {
                        Label("Rain: \(String(format: "%.1f", s.avgPrecipMM)) mm", systemImage: "cloud.rain")
                        Label("Wind: \(Int(round(s.avgWindKPH))) km/h", systemImage: "wind")
                    }
                    .font(.subheadline)
                    Text("Based on historical NASA POWER data for this day of year at your selected location.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.yellow.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var locationPromptCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.title3)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 6) {
                Text("Pick a location to see odds")
                    .font(.subheadline.weight(.semibold))
                Text("Choose a place and date, then we'll crunch the NASA data for you.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            NavigationLink {
                LocationDateView()
            } label: {
                Text("Select")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(.thinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.yellow.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Charts

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Odds snapshot")
                .font(.headline)
            Chart(app.results) { r in
                BarMark(
                    x: .value("Metric", r.label),
                    y: .value("Chance", r.valuePercent)
                )
                .foregroundStyle(.yellow)
                .annotation(position: .top, alignment: .center) {
                    Text("\(Int(r.valuePercent))%")
                        .font(.caption).bold()
                        .padding(2)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .chartYAxisLabel("%")
            .frame(height: 220)
        }
        .padding()
        .background(.thinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.yellow.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var breakdownList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Breakdown")
                .font(.headline)

            ForEach(app.results) { r in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: r.systemIcon)
                        .frame(width: 26)
                        .foregroundStyle(.primary)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(r.label).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(Int(r.valuePercent))%")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text(r.note).font(.footnote).foregroundStyle(.secondary)
                        Capsule().fill(Color.yellow.opacity(0.2)).frame(height: 6)
                            .overlay(
                                GeometryReader { geo in
                                    Capsule().fill(gradient(for: r.valuePercent))
                                        .frame(width: geo.size.width * CGFloat(r.valuePercent / 100.0))
                                }
                            )
                    }
                }
                .padding()
                .background(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.yellow.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How to read these odds")
                .font(.headline)
            Text("Percentages show the share of past years where conditions exceeded your comfort threshold on this same day of year.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("For example, 30% for rain ≥ 5 mm means that in about 3 out of 10 past years, daily rainfall was at least 5 mm on this date.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Note: This is a climatology-based snapshot, not a real-time forecast.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.yellow.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.headline)
            Text(summaryLine())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.yellow.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var actionRow: some View {
        HStack {
            NavigationLink {
                LocationDateView()
            } label: {
                Label("Try another date", systemImage: "calendar.badge.plus")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.yellow.opacity(0.25), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
            }

            Button {
                do {
                    let url = try exportJSON()
                    // Ensure file exists and is non-empty before presenting
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                       let size = attrs[.size] as? NSNumber, size.intValue > 0 {
                        exportItem = ExportItem(url: url)
                    } else {
                        localError = "Export file was empty. Please try again."
                    }
                } catch {
                    localError = "Failed to export JSON. Please try again."
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.yellow.opacity(0.25), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
            }
        }
    }

    // MARK: - Export JSON
    private struct ExportPayload: Codable {
        struct CoordinatePayload: Codable { let latitude: Double; let longitude: Double }
        struct ResultPayload: Codable { let label: String; let valuePercent: Double; let note: String; let systemIcon: String }
        struct WeatherSummaryPayload: Codable { let avgHighC: Double; let avgLowC: Double; let avgPrecipMM: Double; let avgWindKPH: Double }

        let appName: String
        let generatedAt: Date
        let locationName: String?
        let coordinate: CoordinatePayload?
        let date: Date
        let presetName: String?
        let customMaxHot: Double?
        let customMinCold: Double?
        let customMaxRain: Double?
        let customMaxWind: Double?
        let results: [ResultPayload]
        let weatherSummary: WeatherSummaryPayload?
        let note: String
    }

    private func makeExportPayload() -> ExportPayload {
        let coordPayload: ExportPayload.CoordinatePayload? = app.coordinate.map { .init(latitude: $0.latitude, longitude: $0.longitude) }
        let resultsPayload = app.results.map { ExportPayload.ResultPayload(label: $0.label, valuePercent: $0.valuePercent, note: $0.note, systemIcon: $0.systemIcon) }
        let wsPayload: ExportPayload.WeatherSummaryPayload? = app.weatherSummary.map { .init(avgHighC: $0.avgHighC, avgLowC: $0.avgLowC, avgPrecipMM: $0.avgPrecipMM, avgWindKPH: $0.avgWindKPH) }
        return ExportPayload(
            appName: "GeoPulse",
            generatedAt: Date(),
            locationName: app.placename,
            coordinate: coordPayload,
            date: app.selectedDate,
            presetName: app.selectedPreset?.name,
            customMaxHot: app.customMaxHot,
            customMinCold: app.customMinCold,
            customMaxRain: app.customMaxRain,
            customMaxWind: app.customMaxWind,
            results: resultsPayload,
            weatherSummary: wsPayload,
            note: "This is a probability snapshot from historical NASA data (climatology), not a forecast."
        )
    }

    private func exportJSON() throws -> URL {
        let payload = makeExportPayload()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(payload)
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: app.selectedDate)
        let fileURL = tmpDir.appendingPathComponent("GeoPulse-Results-\(dateStr).json")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    // MARK: - Logic

    private func tryLoadIfReady() async {
        guard app.coordinate != nil else { return }
        await loadOdds()
    }

    private func loadOdds() async {
        guard let coord = app.coordinate else {
            return
        }
        app.isLoading = true
        app.errorMessage = nil
        localError = nil

        // Resolve thresholds (custom overrides > preset)
        let hot  = app.customMaxHot ?? app.selectedPreset?.maxHotC
        let cold = app.customMinCold ?? app.selectedPreset?.minColdC
        let rain = app.customMaxRain ?? app.selectedPreset?.maxRainMM
        let wind = app.customMaxWind ?? app.selectedPreset?.maxWindKPH

        do {
            let tuple = try await NASAPowerDirect.fetchComputeWithSummary(
                coord: coord,
                date: app.selectedDate,
                maxHotC: hot,
                minColdC: cold,
                maxRainMM: rain,
                maxWindKPH: wind
            )
            await MainActor.run {
                app.results = tuple.results
                app.weatherSummary = tuple.summary
                app.isLoading = false
            }
        } catch {
            await MainActor.run {
                app.errorMessage = "Failed to fetch NASA data. Please try again."
                app.isLoading = false
            }
        }
    }

    private var chosenPresetName: String? {
        app.selectedPreset?.emoji.appending(" \(app.selectedPreset?.name ?? "")")
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .full
        return f.string(from: date)
    }

    private func gradient(for percent: Double) -> LinearGradient {
        let stops: [Gradient.Stop] = [
            .init(color: .yellow, location: 0.0),
            .init(color: .orange, location: 1.0)
        ]
        return LinearGradient(gradient: Gradient(stops: stops), startPoint: .leading, endPoint: .trailing)
    }

    private func summaryLine() -> String {
        guard !app.results.isEmpty else { return "No data to summarize yet." }
        let top = app.results.max(by: { $0.valuePercent < $1.valuePercent })!
        switch top.systemIcon {
        case "thermometer.sun":
            return "Heat is your biggest risk on this date. Consider earlier start times or shaded venues."
        case "cloud.rain":
            return "Rain is the main concern. Have a backup canopy or venue."
        case "wind":
            return "Wind could be disruptive. Secure decor and avoid tall umbrellas."
        case "thermometer.snowflake":
            return "Cold is the main discomfort. Plan for layers and warm drinks."
        default:
            return "Mixed risks. Keep an eye on heat, rain, and wind when planning."
        }
    }

    private func errorCard(text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(text).font(.subheadline)
            Spacer()
        }
        .padding()
        .background(.thinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.yellow.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func exportSummary() -> String {
        let loc = app.placename ?? "Selected Location"
        let date = dateString(app.selectedDate)
        let lines = app.results.map { "• \($0.label): \(Int($0.valuePercent))%" }.joined(separator: "\n")
        return """
        GeoPulse — Weather Odds
        Location: \(loc)
        Date: \(date)

        \(lines)

        Note: This is a probability snapshot from historical NASA data, not a forecast.
        """
    }
}

// MARK: - ShareSheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        ResultsView().environmentObject(AppState())
    }
}
