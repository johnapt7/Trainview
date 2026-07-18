import Foundation
import AuthenticationServices

/// Owns the Apple-account session and keeps home stations in sync with
/// the backend. (The API also carries a favourites list from the app's
/// earlier design; it is sent empty and ignored on pull.) The app is fully functional signed out — both
/// station stores stay local-first, and this store layers sync on top.
///
/// Sync algorithm, in full: on sign-in, server wins unless the server is
/// empty and the device isn't, in which case the device's lists are pushed
/// up. After that every local change pushes the full lists (debounced) and
/// launch/foreground pulls — last write wins. There is deliberately no
/// merge logic beyond this.
@Observable
final class AccountStore {
    static let shared = AccountStore()

    private static let tokenAccount = "sessionToken"
    private static let userKey = "accountUser"

    private(set) var user: AccountUser?
    /// Set when sign-in fails so the sheet can show an inline message.
    var signInError: String?

    private var token: String?
    private var pushTask: Task<Void, Never>?
    private var needsUpload = false
    private var uploadInFlight = false

    var isSignedIn: Bool { user != nil && token != nil }

    private init() {
        token = KeychainHelper.read(account: Self.tokenAccount)
        if let data = UserDefaults.standard.data(forKey: Self.userKey) {
            user = try? JSONDecoder().decode(AccountUser.self, from: data)
        }
        // A token without a cached user (or vice versa) is a half-written
        // state from a crash — treat as signed out.
        if token == nil || user == nil {
            token = nil
            user = nil
        }
        APIClient.shared.sessionTokenProvider = { [weak self] in self?.token }
    }

    // MARK: - Sign in

    @MainActor
    func handleAuthorization(_ result: Result<ASAuthorization, Error>) {
        signInError = nil
        switch result {
        case .failure(let error):
            // User cancelling the Apple sheet is not an error worth showing.
            if (error as? ASAuthorizationError)?.code != .canceled {
                signInError = "Sign in didn't complete. Please try again."
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                signInError = "Sign in didn't complete. Please try again."
                return
            }
            var fullName: String?
            if let components = credential.fullName {
                let formatted = PersonNameComponentsFormatter().string(from: components)
                if !formatted.isEmpty { fullName = formatted }
            }
            var authorizationCode: String?
            if let codeData = credential.authorizationCode {
                authorizationCode = String(data: codeData, encoding: .utf8)
            }
            Task { await self.signIn(identityToken: identityToken, fullName: fullName, authorizationCode: authorizationCode) }
        }
    }

    @MainActor
    private func signIn(identityToken: String, fullName: String?, authorizationCode: String?) async {
        do {
            let response = try await APIClient.shared.signInWithApple(
                identityToken: identityToken, fullName: fullName, authorizationCode: authorizationCode
            )
            token = response.token
            user = response.user
            KeychainHelper.save(response.token, account: Self.tokenAccount)
            if let data = try? JSONEncoder().encode(response.user) {
                UserDefaults.standard.set(data, forKey: Self.userKey)
            }
            await initialSync()
        } catch {
            signInError = "Couldn't reach the server. Please try again later."
        }
    }

    /// The sign-in merge rule: server wins, unless the server is empty and
    /// the device has data — then push local up.
    @MainActor
    private func initialSync() async {
        do {
            let remote = try await APIClient.shared.getAccountStations()
            let localHome = HomeStationsStore.shared.stations
            if remote.home.isEmpty && !localHome.isEmpty {
                await pushNow()
            } else {
                apply(remote)
            }
        } catch {
            handleSyncError(error)
        }
    }

    // MARK: - Ongoing sync

    /// Called by the station stores after every local save. Debounced so a
    /// burst of edits becomes one PUT.
    func noteStationsChanged() {
        guard isSignedIn else { return }
        needsUpload = true
        pushTask?.cancel()
        pushTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await pushNow()
        }
    }

    @MainActor
    private func pushNow() async {
        guard isSignedIn else { return }
        uploadInFlight = true
        defer { uploadInFlight = false }
        do {
            _ = try await APIClient.shared.putAccountStations(
                home: HomeStationsStore.shared.stations.map(SyncedStation.init),
                favourites: []
            )
            needsUpload = false
        } catch {
            handleSyncError(error)
        }
    }

    /// Pull on launch/foreground. Skipped while a local edit is waiting to
    /// upload — unsynced local changes must not be reverted by a stale GET.
    func refresh() {
        guard isSignedIn else { return }
        Task { @MainActor in
            if needsUpload || uploadInFlight {
                await pushNow()
                return
            }
            do {
                apply(try await APIClient.shared.getAccountStations())
            } catch {
                handleSyncError(error)
            }
        }
    }

    @MainActor
    private func apply(_ payload: StationsPayload) {
        HomeStationsStore.shared.replaceAll(payload.home.map(\.asStation), fromSync: true)
    }

    @MainActor
    private func handleSyncError(_ error: Error) {
        // An invalid/expired session silently signs out and keeps local
        // data; anything else (offline etc.) leaves needsUpload set so the
        // next foreground retries.
        if case APIError.unauthorized = error {
            clearSession()
        }
    }

    // MARK: - Sign out / delete

    @MainActor
    func signOut() {
        Task { try? await APIClient.shared.signOut() }
        clearSession()
    }

    @MainActor
    func deleteAccount() async throws {
        try await APIClient.shared.deleteAccount()
        clearSession()
    }

    /// Local lists always survive — only the session and cached identity go.
    @MainActor
    private func clearSession() {
        pushTask?.cancel()
        needsUpload = false
        token = nil
        user = nil
        KeychainHelper.delete(account: Self.tokenAccount)
        UserDefaults.standard.removeObject(forKey: Self.userKey)
    }
}
