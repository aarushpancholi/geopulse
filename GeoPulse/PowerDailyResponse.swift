//
//  PowerDailyResponse.swift
//  GeoPulse
//
//  Created by Aarush Pancholi on 10/4/25.
//


import Foundation
import CoreLocation

// MARK: - NASA POWER response model
struct PowerDailyResponse: Decodable {
    struct Properties: Decodable {
        struct Parameter: Decodable {
            let T2M_MAX: [String: Double]?
            let T2M_MIN: [String: Double]?
            let PRECTOTCORR: [String: Double]?
            let WS10M: [String: Double]?
        }
        let parameter: Parameter
    }
    let properties: Properties
}

// MARK: - Direct NASA POWER client + odds calculator
enum NASAPowerDirect {
    /// Years of history to use (adjust if you like)
    private static let startYear = 1981
    private static let endYear   = 2020

    /// In-memory cache to avoid re-downloading for same lat/lon session
    private static var cache: [String: PowerDailyResponse] = [:]

    static func fetchAndCompute(
        coord: CLLocationCoordinate2D,
        date: Date,
        maxHotC: Double?,
        minColdC: Double?,
        maxRainMM: Double?,
        maxWindKPH: Double?
    ) async throws -> [OddsResult] {

        let key = "\(round(coord.latitude*10000)/10000),\(round(coord.longitude*10000)/10000)"
        let data = try await fetchPOWER(lat: coord.latitude, lon: coord.longitude, cacheKey: key)

        let params = data.properties.parameter
        let tmax = params.T2M_MAX ?? [:]
        let tmin = params.T2M_MIN ?? [:]
        let precip = params.PRECTOTCORR ?? [:]
        let ws = params.WS10M ?? [:]

        let cal = Calendar(identifier: .gregorian)
        let targetDOY = cal.ordinality(of: .day, in: .year, for: date) ?? 1

        func doy(_ yyyymmdd: String) -> Int {
            let y = Int(yyyymmdd.prefix(4)) ?? 2000
            let m = Int(yyyymmdd.dropFirst(4).prefix(2)) ?? 1
            let d = Int(yyyymmdd.suffix(2)) ?? 1
            if let dt = cal.date(from: DateComponents(year: y, month: m, day: d)) {
                return cal.ordinality(of: .day, in: .year, for: dt) ?? 1
            }
            return 1
        }

        // Collect same day-of-year across years (exact-match window; you can widen to +/- 1–2 days for smoothing)
        struct Row { let tmax: Double; let tmin: Double; let p: Double; let windKph: Double }
        var rows: [Row] = []
        for (k, tx) in tmax {
            if doy(k) == targetDOY {
                let tn = tmin[k] ?? tx // fallback if T2M_MIN missing for that key
                let p  = precip[k] ?? 0
                let windKph = (ws[k] ?? 0) * 3.6 // m/s → km/h
                rows.append(Row(tmax: tx, tmin: tn, p: p, windKph: windKph))
            }
        }

        let n = max(rows.count, 1)
        func pct(_ count: Int) -> Double { (Double(count) / Double(n)) * 100.0 }

        var out: [OddsResult] = []

        if let hot = maxHotC {
            let count = rows.filter { $0.tmax > hot }.count
            out.append(.init(label: "Too hot > \(Int(hot)) °C",
                             valuePercent: pct(count),
                             note: "Historical odds of hotter-than-threshold.",
                             systemIcon: "thermometer.sun"))
        }
        if let cold = minColdC {
            // Use T2M_MIN if available, else compare against T2M_MAX fallback above
            let count = rows.filter { $0.tmin < cold }.count
            out.append(.init(label: "Too cold < \(Int(cold)) °C",
                             valuePercent: pct(count),
                             note: "Historical odds of colder-than-threshold.",
                             systemIcon: "thermometer.snowflake"))
        }
        if let r = maxRainMM {
            let count = rows.filter { $0.p >= r }.count
            out.append(.init(label: "Rain ≥ \(Int(r)) mm",
                             valuePercent: pct(count),
                             note: "Daily precipitation exceedance odds.",
                             systemIcon: "cloud.rain"))
        }
        if let w = maxWindKPH {
            let count = rows.filter { $0.windKph >= w }.count
            out.append(.init(label: "Wind ≥ \(Int(w)) km/h",
                             valuePercent: pct(count),
                             note: "Daily wind exceedance odds.",
                             systemIcon: "wind"))
        }

        return out
    }

    static func fetchComputeWithSummary(
        coord: CLLocationCoordinate2D,
        date: Date,
        maxHotC: Double?,
        minColdC: Double?,
        maxRainMM: Double?,
        maxWindKPH: Double?
    ) async throws -> (results: [OddsResult], summary: WeatherSummary?) {
        let key = "\(round(coord.latitude*10000)/10000),\(round(coord.longitude*10000)/10000)"
        let data = try await fetchPOWER(lat: coord.latitude, lon: coord.longitude, cacheKey: key)

        let params = data.properties.parameter
        let tmax = params.T2M_MAX ?? [:]
        let tmin = params.T2M_MIN ?? [:]
        let precip = params.PRECTOTCORR ?? [:]
        let ws = params.WS10M ?? [:]

        let cal = Calendar(identifier: .gregorian)
        let targetDOY = cal.ordinality(of: .day, in: .year, for: date) ?? 1

        func doy(_ yyyymmdd: String) -> Int {
            let y = Int(yyyymmdd.prefix(4)) ?? 2000
            let m = Int(yyyymmdd.dropFirst(4).prefix(2)) ?? 1
            let d = Int(yyyymmdd.suffix(2)) ?? 1
            if let dt = cal.date(from: DateComponents(year: y, month: m, day: d)) {
                return cal.ordinality(of: .day, in: .year, for: dt) ?? 1
            }
            return 1
        }

        struct Row { let tmax: Double; let tmin: Double; let p: Double; let windKph: Double }
        var rows: [Row] = []
        for (k, tx) in tmax {
            if doy(k) == targetDOY {
                let tn = tmin[k] ?? tx
                let p  = precip[k] ?? 0
                let windKph = (ws[k] ?? 0) * 3.6
                rows.append(Row(tmax: tx, tmin: tn, p: p, windKph: windKph))
            }
        }

        // Compute odds using existing logic by reusing fetchAndCompute to avoid duplication
        let odds = try await fetchAndCompute(coord: coord, date: date, maxHotC: maxHotC, minColdC: minColdC, maxRainMM: maxRainMM, maxWindKPH: maxWindKPH)

        guard !rows.isEmpty else {
            return (odds, nil)
        }

        let avgHigh = rows.map { $0.tmax }.reduce(0, +) / Double(rows.count)
        let avgLow  = rows.map { $0.tmin }.reduce(0, +) / Double(rows.count)
        let avgP    = rows.map { $0.p }.reduce(0, +) / Double(rows.count)
        let avgW    = rows.map { $0.windKph }.reduce(0, +) / Double(rows.count)

        let summary = WeatherSummary(avgHighC: avgHigh, avgLowC: avgLow, avgPrecipMM: avgP, avgWindKPH: avgW)
        return (odds, summary)
    }

    private static func fetchPOWER(lat: Double, lon: Double, cacheKey: String) async throws -> PowerDailyResponse {
        if let cached = cache[cacheKey] { return cached }

        // Request T2M_MAX, T2M_MIN, precipitation, and 10m wind
        let urlStr = "https://power.larc.nasa.gov/api/temporal/daily/point?parameters=T2M_MAX,T2M_MIN,PRECTOTCORR,WS10M&community=RE&longitude=\(lon)&latitude=\(lat)&start=\(startYear)&end=\(endYear)&format=JSON"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.setValue("GeoPulse iOS (educational app)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 30

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(PowerDailyResponse.self, from: data)
        cache[cacheKey] = decoded
        return decoded
    }
}
