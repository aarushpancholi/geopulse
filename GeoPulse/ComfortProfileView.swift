//
//  ComfortProfileView.swift
//  GeoPulse
//
//  Created by Aarush Pancholi on 10/4/25.
//

import SwiftUI

struct ComfortProfileView: View {
    @EnvironmentObject var app: AppState
    @State private var showAdvanced = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header

                presetGrid

                DisclosureGroup(isExpanded: $showAdvanced) {
                    advancedControls
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.2.rectangle")
                        Text("Advanced (optional)")
                            .fontWeight(.semibold)
                    }
                }
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.yellow.opacity(0.25), lineWidth: 1)
                )

                NavigationLink {
                    ResultsView()
                } label: {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                        Text("View Weather Odds")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.yellow.opacity(0.25), lineWidth: 1)
                    )
                }
                .disabled(app.selectedPreset == nil && !hasCustoms)
            }
            .padding()
        }
        .navigationTitle("Comfort Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pick a simple preset")
                .font(.headline)
            Text("These map to temperature / rain / wind thresholds behind the scenes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var presetGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(app.presets) { preset in
                Button {
                    app.selectedPreset = preset
                    // Clear custom tweaks when selecting a preset
                    app.customMaxHot = nil
                    app.customMinCold = nil
                    app.customMaxRain = nil
                    app.customMaxWind = nil
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(preset.emoji).font(.title2)
                            Text(preset.name).font(.headline)
                            Spacer()
                            if app.selectedPreset == preset {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.yellow)
                            }
                        }
                        Text(preset.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Divider().opacity(0.3)

                        thresholdsRow(preset: preset)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(cardBackground(selected: app.selectedPreset == preset))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.yellow.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func cardBackground(selected: Bool) -> AnyShapeStyle {
        if selected {
            return AnyShapeStyle(Color.yellow.opacity(0.16))
        } else {
            return AnyShapeStyle(.thinMaterial)
        }
    }

    private func thresholdsRow(preset: ComfortPreset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let v = preset.maxHotC { Tag(text: "Hot > \(Int(v))°C", system: "thermometer.sun") }
                if let v = preset.minColdC { Tag(text: "Cold < \(Int(v))°C", system: "thermometer.snowflake") }
            }
            HStack(spacing: 10) {
                if let v = preset.maxRainMM { Tag(text: "Rain ≥ \(Int(v))mm", system: "cloud.rain") }
                if let v = preset.maxWindKPH { Tag(text: "Wind ≥ \(Int(v))km/h", system: "wind") }
            }
        }
    }

    private var advancedControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tweak thresholds to your liking.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Group {
                ToggleWithStepper(title: "Too hot >", unit: "°C", range: 20...45, value: Binding(
                    get: { app.customMaxHot ?? app.selectedPreset?.maxHotC ?? 30 },
                    set: { app.customMaxHot = $0 }
                ))
                ToggleWithStepper(title: "Too cold <", unit: "°C", range: -5...20, value: Binding(
                    get: { app.customMinCold ?? app.selectedPreset?.minColdC ?? 10 },
                    set: { app.customMinCold = $0 }
                ))
                ToggleWithStepper(title: "Rain ≥", unit: "mm", range: 1...50, value: Binding(
                    get: { app.customMaxRain ?? app.selectedPreset?.maxRainMM ?? 10 },
                    set: { app.customMaxRain = $0 }
                ))
                ToggleWithStepper(title: "Wind ≥", unit: "km/h", range: 5...80, value: Binding(
                    get: { app.customMaxWind ?? app.selectedPreset?.maxWindKPH ?? 30 },
                    set: { app.customMaxWind = $0 }
                ))
            }
        }
        .padding(.top, 6)
    }

    private var hasCustoms: Bool {
        [app.customMaxHot, app.customMinCold, app.customMaxRain, app.customMaxWind].contains { $0 != nil }
    }
}

// MARK: - Small UI helpers

private struct Tag: View {
    let text: String
    let system: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: system)
            Text(text)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.yellow.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct ToggleWithStepper: View {
    let title: String
    let unit: String
    let range: ClosedRange<Double>
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(title) \(Int(value))\(unit)")
                .font(.subheadline)
            Slider(value: $value, in: range, step: 1)
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.25), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        ComfortProfileView().environmentObject(AppState())
    }
}

