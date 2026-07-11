import SwiftUI

struct TrackingConfirmationSheet: View {
    let train: Train
    let stops: [Stop]
    let boardingStation: Station
    let tracker: TrainTracker
    let accent: Color
    @Environment(\.dismiss) private var dismiss
    @State private var alightingCRS: String = ""

    private var brand: OperatorBrand {
        OperatorBrand.brand(for: train.operatorCode)
    }

    /// Stops after the boarding station — the places the user could get off.
    /// Empty when boarding at the terminus (arrivals tracking), in which case
    /// the picker is hidden and tracking follows the whole service.
    private var alightingOptions: [Stop] {
        guard let idx = stops.firstIndex(where: { $0.crs == boardingStation.code }),
              idx + 1 < stops.count else { return [] }
        return Array(stops[(idx + 1)...])
    }

    private var selectedAlighting: Stop? {
        alightingOptions.first { $0.crs == alightingCRS } ?? alightingOptions.last
    }

    /// Stops on the user's journey: boarding station → selected alighting stop.
    private var personalStopCount: Int {
        guard let selected = selectedAlighting,
              let idx = alightingOptions.firstIndex(where: { $0.crs == selected.crs }) else {
            return max(stops.count - 1, 0)
        }
        return idx + 1
    }

    var body: some View {
        VStack(spacing: 0) {
            handle
            ScrollView(showsIndicators: false) {
                content
            }
        }
        .background(Theme.cream)
        .presentationDetents([.fraction(0.8)])
        .presentationDragIndicator(.hidden)
        .onAppear {
            alightingCRS = alightingOptions.last?.crs ?? ""
        }
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Theme.ink.opacity(0.2))
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 20)
    }

    private var content: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("TRACK THIS TRAIN")
                    .font(.mono(10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.inkMute)
                Text("Live journey tracking")
                    .font(.display(26, weight: .medium))
                    .tracking(-0.3)
            }

            trainSummary

            if !alightingOptions.isEmpty {
                alightingPicker
            }

            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "location.fill", text: "See which stop the train is at in real time")
                featureRow(icon: "bell.fill", text: "Alerts for platform changes, delays — and when your stop is next")
                featureRow(icon: "rectangle.stack.fill", text: "Track from the lock screen with Live Activity")
            }
            .padding(16)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 10) {
                Button {
                    tracker.startTracking(
                        train: train,
                        stops: stops,
                        boardingStation: boardingStation,
                        alightingCRS: selectedAlighting?.crs
                    )
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 13))
                        Text("Start Tracking")
                            .font(.ui(15, weight: .semibold))
                    }
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.ink)
                    .clipShape(Capsule())
                }

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.ui(13, weight: .medium))
                        .foregroundStyle(Theme.inkMute)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
    }

    private var trainSummary: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                Text(train.operatorCode)
                    .font(.mono(9, weight: .bold))
                    .tracking(0.5)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(brand.bg)
                    .foregroundStyle(brand.fg)
                Text(train.operator)
                    .font(.ui(11, weight: .medium))
                    .foregroundStyle(brand.label)
                    .lineLimit(1)
                    .padding(.leading, 6)
                    .padding(.trailing, 8)
                    .padding(.vertical, 4)
            }
            .background(brand.bg.opacity(0.1))
            .clipShape(Capsule())

            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 2) {
                    Text(train.time)
                        .font(.mono(18, weight: .medium))
                    Text(boardingStation.name)
                        .font(.ui(12))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkMute)
                    Text("\(personalStopCount) stop\(personalStopCount == 1 ? "" : "s")")
                        .font(.mono(9, weight: .medium))
                        .tracking(0.3)
                        .foregroundStyle(Theme.inkMute)
                }

                VStack(spacing: 2) {
                    Text(selectedAlighting?.time ?? stops.last?.time ?? "")
                        .font(.mono(18, weight: .medium))
                    Text(selectedAlighting?.station ?? train.destination)
                        .font(.ui(12))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// "Where are you getting off?" — defaults to the train's terminus. The
    /// tracker trims the journey here, so the countdown, Live Activity, and
    /// the "your stop is next" alert are all about this stop.
    private var alightingPicker: some View {
        Menu {
            Picker("Getting off at", selection: $alightingCRS) {
                ForEach(alightingOptions, id: \.crs) { stop in
                    Text("\(stop.station) · \(stop.time)").tag(stop.crs)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 26, height: 26)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text("GETTING OFF AT")
                        .font(.mono(9, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(Theme.inkMute)
                    Text(selectedAlighting?.station ?? "")
                        .font(.ui(14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
                Spacer()
                if let time = selectedAlighting?.time, !time.isEmpty {
                    Text(time)
                        .font(.mono(12, weight: .medium))
                        .foregroundStyle(Theme.inkMute)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkMute)
            }
            .padding(14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Theme.ink)
                .frame(width: 26, height: 26)
                .background(accent)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            Text(text)
                .font(.ui(12))
                .foregroundStyle(Theme.inkSoft)
        }
    }
}
