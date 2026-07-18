import SwiftUI

/// Operator status board: every operator with a simple green or red
/// indicator. Station-specific detail lives on the station screens, so
/// this tab stays a pure at-a-glance summary.
struct DisruptionsScreen: View {
    let accent: Color

    @State private var indicators: [TOCIndicator] = []
    @State private var indicatorsLoaded = false
    @State private var loadError = false

    private var disrupted: [TOCIndicator] {
        indicators.filter { $0.status != "Good service" }
    }

    private var healthy: [TOCIndicator] {
        indicators.filter { $0.status == "Good service" }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if loadError {
                        errorCard
                    } else if !indicatorsLoaded {
                        loadingCard
                    } else {
                        summaryHeader
                        operatorList
                    }
                    Color.clear.frame(height: 32)
                }
            }
        }
        .background(Theme.cream)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Chrome

    private var topBar: some View {
        Text("DISRUPTIONS")
            .font(.mono(11, weight: .semibold))
            .tracking(2)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(Theme.cream)
    }

    private var summaryHeader: some View {
        HStack(spacing: 8) {
            Text("\(indicators.count)")
                .font(.display(42))
                .tracking(-1)
            VStack(alignment: .leading, spacing: 0) {
                Text("operators")
                Text("tracked")
            }
            .font(.mono(11))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Theme.inkSoft)
            Spacer()
            if disrupted.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                    Text("All clear")
                        .font(.mono(11, weight: .semibold))
                        .tracking(0.4)
                }
                .foregroundStyle(Theme.perfGood)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.perfGood.opacity(0.12))
                .clipShape(Capsule())
            } else {
                Text("\(disrupted.count) disrupted")
                    .font(.mono(11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Theme.delayedText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.warn.opacity(0.3))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    // MARK: - Operators

    /// Disrupted operators surface first; each row is just identity plus a
    /// green/red dot — deliberately no expansion or detail.
    private var operatorList: some View {
        VStack(spacing: 0) {
            ForEach(Array((disrupted + healthy).enumerated()), id: \.element.tocCode) { index, toc in
                operatorRow(toc)
                    .overlay(alignment: .bottom) {
                        if index < indicators.count - 1 {
                            Divider().overlay(Theme.line)
                        }
                    }
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 18)
        .padding(.top, 20)
    }

    private func operatorRow(_ toc: TOCIndicator) -> some View {
        let brand = OperatorBrand.brand(for: toc.tocCode)
        let isGood = toc.status == "Good service"

        return HStack(spacing: 10) {
            Text(toc.tocCode)
                .font(.mono(9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(brand.fg)
                .frame(width: 32, height: 26)
                .background(brand.bg)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text(toc.tocName)
                .font(.ui(13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer()
            Circle()
                .fill(isGood ? Theme.perfGood : Theme.cancelledText)
                .frame(width: 10, height: 10)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Loading & error

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(Theme.ink)
            Text("Checking the network...")
                .font(.ui(13))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private var errorCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 18))
                .foregroundStyle(Theme.inkMute)
                .padding(.bottom, 2)
            Text("Couldn't load network status")
                .font(.display(18))
            Text("Check your connection and try again")
                .font(.ui(11))
                .foregroundStyle(Theme.inkMute)
            Button {
                Task { await load() }
            } label: {
                Text("Try again")
                    .font(.ui(13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(accent)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    // MARK: - Data

    private func load() async {
        loadError = false
        do {
            indicators = try (await APIClient.shared.getTOCIndicators()).indicators
            indicatorsLoaded = true
        } catch {
            if !indicatorsLoaded { loadError = true }
        }
    }
}
