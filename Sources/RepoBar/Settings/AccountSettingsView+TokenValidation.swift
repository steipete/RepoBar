import Foundation
import RepoBarCore
import SwiftUI

extension AccountSettingsView {
    func validateToken() async {
        guard case .loggedIn = self.session.account else { return }

        if self.tokenValidation == .checking {
            return
        }
        self.tokenValidation = .checking
        let started = Date()
        await self.logAuth("Auth: token check started")
        do {
            let user = try await self.withTimeout(seconds: self.tokenCheckTimeout) {
                try await self.appState.github.currentUser()
            }
            self.session.account = .loggedIn(user)
            self.session.lastError = nil
            self.tokenValidation = .valid
            await self.logAuth("Auth: token check ok in \(Self.formatElapsed(since: started))")
        } catch {
            if error.isAuthenticationFailure {
                self.tokenValidation = .invalid("Authentication required.")
                await self.logAuth("Auth: token check auth failure in \(Self.formatElapsed(since: started))")
                await self.appState.handleAuthenticationFailure(error)
                return
            }
            self.tokenValidation = .invalid(error.userFacingMessage)
            await self.logAuth("Auth: token check failed in \(Self.formatElapsed(since: started)): \(error.userFacingMessage)")
        }
    }

    func refreshToken() async {
        guard case .loggedIn = self.session.account else { return }

        if self.tokenValidation == .checking {
            return
        }
        self.tokenValidation = .checking
        let started = Date()
        await self.logAuth("Auth: token refresh started")
        do {
            let refreshed = try await self.withTimeout(seconds: self.tokenRefreshTimeout) {
                try await self.appState.auth.refreshIfNeeded(force: true)
            }
            guard refreshed != nil else {
                throw URLError(.userAuthenticationRequired)
            }

            await self.logAuth("Auth: token refresh ok in \(Self.formatElapsed(since: started))")
            await self.validateToken()
        } catch {
            if error.isAuthenticationFailure {
                self.tokenValidation = .invalid("Authentication required.")
                await self.logAuth("Auth: token refresh auth failure in \(Self.formatElapsed(since: started))")
                await self.appState.handleAuthenticationFailure(error)
                return
            }
            self.tokenValidation = .invalid(error.userFacingMessage)
            await self.logAuth("Auth: token refresh failed in \(Self.formatElapsed(since: started)): \(error.userFacingMessage)")
        }
    }

    var tokenStatusText: String? {
        switch self.tokenValidation {
        case .unknown:
            "Token status not checked yet."
        case .checking:
            "Checking token…"
        case .valid:
            "Token is valid."
        case let .invalid(message):
            "Token invalid: \(message)"
        }
    }

    var tokenStatusColor: Color {
        switch self.tokenValidation {
        case .valid:
            .green
        case .invalid:
            .red
        default:
            .secondary
        }
    }

    func logAuth(_ message: String) async {
        await DiagnosticsLogger.shared.message(message)
    }

    func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    static func formatElapsed(since start: Date) -> String {
        let elapsed = Date().timeIntervalSince(start)
        return String(format: "%.2fs", elapsed)
    }
}

enum TokenValidationState: Equatable {
    case unknown
    case checking
    case valid
    case invalid(String)
}

enum HostMode: String, CaseIterable {
    case githubCom
    case enterprise

    var label: String {
        switch self {
        case .githubCom:
            "GitHub.com"
        case .enterprise:
            "Enterprise"
        }
    }
}
