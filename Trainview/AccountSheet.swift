import SwiftUI
import AuthenticationServices

/// Account management: Sign in with Apple, home-station editing, sign out
/// and account deletion. Presented from the Home screen's person icon.
struct AccountSheet: View {
    let accent: Color
    @Environment(\.dismiss) private var dismiss

    @State private var accountStore = AccountStore.shared
    @State private var homeStore = HomeStationsStore.shared
    @State private var showStationPicker = false
    @State private var showDeleteConfirm = false
    @State private var deleteFailed = false
    @State private var editMode: EditMode = .inactive

    var body: some View {
        VStack(spacing: 0) {
            handle
            header
            if accountStore.isSignedIn {
                signedInContent
            } else {
                signedOutContent
            }
        }
        .background(Theme.cream)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showStationPicker) {
            StationSearchSheet(
                currentStation: "",
                onSelect: { homeStore.add($0) },
                kicker: "ADD HOME STATION",
                title: "Which station?"
            )
        }
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Theme.ink.opacity(0.2))
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 20)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("ACCOUNT")
                .font(.mono(10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.inkMute)
            Text(accountStore.isSignedIn ? displayName : "Sync your stations")
                .font(.display(26, weight: .medium))
                .tracking(-0.3)
                .lineLimit(1)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 20)
    }

    private var displayName: String {
        if let name = accountStore.user?.displayName, !name.isEmpty { return name }
        if let email = accountStore.user?.email, !email.isEmpty { return email }
        return "Apple Account"
    }

    // MARK: - Signed out

    private var signedOutContent: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("Sign in to keep your home stations backed up across devices.")
                    .font(.ui(14))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Text("The app works fully without an account.")
                    .font(.ui(12))
                    .foregroundStyle(Theme.inkMute)
            }
            .padding(.horizontal, 30)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                accountStore.handleAuthorization(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .padding(.horizontal, 22)

            if let error = accountStore.signInError {
                Text(error)
                    .font(.ui(12))
                    .foregroundStyle(Theme.cancelledText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Signed in

    private var signedInContent: some View {
        List {
            Section {
                ForEach(homeStore.stations) { station in
                    HStack(spacing: 12) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkMute)
                            .frame(width: 28, height: 28)
                            .background(accent.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(station.name)
                                .font(.ui(14, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Text(station.code)
                                .font(.mono(10, weight: .medium))
                                .tracking(0.8)
                                .foregroundStyle(Theme.inkMute)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
                .onDelete(perform: removeAt)
                .onMove { homeStore.move(fromOffsets: $0, toOffset: $1) }

                if homeStore.stations.count < HomeStationsStore.maxStations {
                    Button {
                        showStationPicker = true
                    } label: {
                        Label("Add home station", systemImage: "plus.circle.fill")
                            .font(.ui(14, weight: .medium))
                            .foregroundStyle(Theme.ink)
                    }
                    .listRowBackground(Theme.card)
                }
            } header: {
                HStack {
                    Text("HOME STATIONS")
                        .font(.mono(10, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.inkMute)
                    Spacer()
                    if homeStore.stations.count > 1 {
                        Button(editMode == .active ? "DONE" : "REORDER") {
                            withAnimation { editMode = editMode == .active ? .inactive : .active }
                        }
                        .font(.mono(10, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.ink)
                    }
                }
            } footer: {
                Text("Home stations appear at the top of your Home screen with live departures. Swipe a station to remove it; use Reorder to change the order.")
                    .font(.ui(11))
                    .foregroundStyle(Theme.inkMute)
            }

            Section {
                Button {
                    accountStore.signOut()
                    dismiss()
                } label: {
                    Text("Sign out")
                        .font(.ui(14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                }
                .listRowBackground(Theme.card)

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text("Delete account")
                        .font(.ui(14, weight: .medium))
                }
                .listRowBackground(Theme.card)
            } footer: {
                if deleteFailed {
                    Text("Couldn't delete your account. Check your connection and try again.")
                        .font(.ui(11))
                        .foregroundStyle(Theme.cancelledText)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .confirmationDialog(
            "Delete account?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task {
                    do {
                        try await accountStore.deleteAccount()
                        dismiss()
                    } catch {
                        deleteFailed = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and synced stations from our servers. Your lists stay on this device.")
        }
    }

    private func removeAt(_ offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            let station = homeStore.stations[index]
            homeStore.remove(station)
        }
    }
}
