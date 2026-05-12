import SwiftUI

struct TrackingConfirmationSheet: View {
    let train: Train
    let stops: [Stop]
    let boardingStation: Station
    let tracker: TrainTracker
    let accent: Color
    @Environment(\.dismiss) private var dismiss

    private var brand: OperatorBrand {
        OperatorBrand.brand(for: train.operatorCode)
    }

    var body: some View {
        VStack(spacing: 0) {
            handle
            content
        }
        .background(Theme.cream)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
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

            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "location.fill", text: "See which stop the train is at in real time")
                featureRow(icon: "bell.fill", text: "Updates every 30 seconds with latest data")
                featureRow(icon: "rectangle.stack.fill", text: "Track from the lock screen with Live Activity")
            }
            .padding(16)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 10) {
                Button {
                    tracker.startTracking(train: train, stops: stops, boardingStation: boardingStation)
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
                    .foregroundStyle(brand.bg)
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
                    Text(train.origin)
                        .font(.ui(12))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkMute)
                    Text("\(stops.count) stops")
                        .font(.mono(9, weight: .medium))
                        .tracking(0.3)
                        .foregroundStyle(Theme.inkMute)
                }

                VStack(spacing: 2) {
                    Text(stops.last?.time ?? "")
                        .font(.mono(18, weight: .medium))
                    Text(train.destination)
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
