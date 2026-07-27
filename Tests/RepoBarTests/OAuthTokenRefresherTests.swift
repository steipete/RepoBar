import Foundation
@testable import RepoBarCore
import Testing

struct OAuthTokenRefresherTests {
    @Test
    func `refresh uses stored client credentials`() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        try store.save(tokens: OAuthTokens(accessToken: "old", refreshToken: "r1", expiresAt: .distantPast))
        try store.save(clientCredentials: OAuthClientCredentials(clientID: "cid", clientSecret: "csecret"))

        let session = URLSession(configuration: Self.sessionConfiguration())
        let handlerID = UUID().uuidString
        Self.MockURLProtocol.register(handlerID: handlerID) { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString.contains("/login/oauth/access_token") == true)
            let body = try #require(Self.bodyString(from: request))
            #expect(body.contains("client_id=cid"))
            #expect(body.contains("client_secret=csecret"))
            #expect(body.contains("grant_type=refresh_token"))
            #expect(body.contains("refresh_token=r1"))

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            {"access_token":"new","token_type":"bearer","scope":"repo","expires_in":3600,"refresh_token":"r2"}
            """.utf8)
            return (data, response)
        }
        defer { Self.MockURLProtocol.unregister(handlerID: handlerID) }

        let refresher = OAuthTokenRefresher(tokenStore: store) { request in
            let (tagged, boxed) = Self.taggedRequest(request, handlerID: handlerID)
            _ = boxed
            return try await session.data(for: tagged)
        }
        let refreshed = try await refresher.refreshIfNeeded(host: RepoBarAuthDefaults.githubHost)
        #expect(refreshed?.accessToken == "new")
        #expect(try store.load()?.refreshToken == "r2")
    }

    @Test
    func `refresh updates account scoped tokens`() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let accountID = "github.com#alice"
        let store = TokenStore(service: service)
        defer { store.clear(accountID: accountID) }

        try store.save(tokens: OAuthTokens(accessToken: "old", refreshToken: "r1", expiresAt: .distantPast), accountID: accountID)
        try store.save(clientCredentials: OAuthClientCredentials(clientID: "cid", clientSecret: "csecret"), accountID: accountID)

        let session = URLSession(configuration: Self.sessionConfiguration())
        let handlerID = UUID().uuidString
        Self.MockURLProtocol.register(handlerID: handlerID) { request in
            let body = try #require(Self.bodyString(from: request))
            #expect(body.contains("client_id=cid"))
            #expect(body.contains("refresh_token=r1"))

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            {"access_token":"new","token_type":"bearer","scope":"repo","expires_in":3600,"refresh_token":"r2"}
            """.utf8)
            return (data, response)
        }
        defer { Self.MockURLProtocol.unregister(handlerID: handlerID) }

        let refresher = OAuthTokenRefresher(tokenStore: store) { request in
            let (tagged, boxed) = Self.taggedRequest(request, handlerID: handlerID)
            _ = boxed
            return try await session.data(for: tagged)
        }
        let refreshed = try await refresher.refreshIfNeeded(host: RepoBarAuthDefaults.githubHost, accountID: accountID)
        #expect(refreshed?.accessToken == "new")
        #expect(try store.loadTokens(accountID: accountID)?.refreshToken == "r2")
        #expect(try store.load() == nil)
    }

    @Test
    func `concurrent account refreshes share one request`() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let accountID = "github.com#alice"
        let store = TokenStore(service: service)
        defer { store.clear(accountID: accountID) }

        try store.save(
            tokens: OAuthTokens(accessToken: "old", refreshToken: "r1", expiresAt: .distantPast),
            accountID: accountID
        )
        let requestCount = AsyncCallCounter()
        let load: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            await requestCount.increment()
            try await Task.sleep(for: .milliseconds(100))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"access_token":"fresh","token_type":"bearer","scope":"repo","expires_in":3600,"refresh_token":"r2"}"#.utf8)
            return (data, response)
        }
        let firstRefresher = OAuthTokenRefresher(tokenStore: store, load: load)
        let secondRefresher = OAuthTokenRefresher(tokenStore: store, load: load)
        let barrier = AsyncStartBarrier(participants: 12)

        let tokens = try await withThrowingTaskGroup(of: OAuthTokens?.self) { group in
            for index in 0 ..< 12 {
                group.addTask {
                    await barrier.arrive()
                    let refresher = index.isMultiple(of: 2) ? firstRefresher : secondRefresher
                    return try await refresher.refreshIfNeeded(
                        host: RepoBarAuthDefaults.githubHost,
                        accountID: accountID
                    )
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(await requestCount.value == 1)
        #expect(tokens.count == 12)
        #expect(tokens.allSatisfy { $0?.accessToken == "fresh" && $0?.refreshToken == "r2" })
    }

    @Test
    func `concurrent refresh failure is shared by every caller`() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let accountID = "github.com#alice"
        let store = TokenStore(service: service)
        defer { store.clear(accountID: accountID) }

        try store.save(
            tokens: OAuthTokens(accessToken: "old", refreshToken: "revoked", expiresAt: .distantPast),
            accountID: accountID
        )
        let requestCount = AsyncCallCounter()
        let refresher = OAuthTokenRefresher(tokenStore: store) { request in
            await requestCount.increment()
            try await Task.sleep(for: .milliseconds(100))
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"error":"invalid_grant","error_description":"token revoked"}"#.utf8), response)
        }
        let barrier = AsyncStartBarrier(participants: 12)

        let statusCodes = await withTaskGroup(of: Int?.self) { group in
            for _ in 0 ..< 12 {
                group.addTask {
                    await barrier.arrive()
                    do {
                        _ = try await refresher.refreshIfNeeded(
                            host: RepoBarAuthDefaults.githubHost,
                            accountID: accountID
                        )
                        return nil
                    } catch let GitHubAPIError.badStatus(code, _) {
                        return code
                    } catch {
                        return -1
                    }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        #expect(await requestCount.value == 1)
        #expect(statusCodes == Array(repeating: 400, count: 12))
    }

    @Test
    func `forced refresh is not swallowed by concurrent valid token read`() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let accountID = "github.com#alice"
        let store = TokenStore(service: service)
        defer { store.clear(accountID: accountID) }

        try store.save(
            tokens: OAuthTokens(accessToken: "current", refreshToken: "r1", expiresAt: .distantFuture),
            accountID: accountID
        )
        let requestCount = AsyncCallCounter()
        let refresher = OAuthTokenRefresher(tokenStore: store) { request in
            await requestCount.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"access_token":"forced","token_type":"bearer","scope":"repo","expires_in":3600,"refresh_token":"r2"}"#.utf8)
            return (data, response)
        }
        let barrier = AsyncStartBarrier(participants: 2)

        async let regular: OAuthTokens? = {
            await barrier.arrive()
            return try await refresher.refreshIfNeeded(host: RepoBarAuthDefaults.githubHost, accountID: accountID)
        }()
        async let forced: OAuthTokens? = {
            await barrier.arrive()
            return try await refresher.refreshIfNeeded(host: RepoBarAuthDefaults.githubHost, force: true, accountID: accountID)
        }()
        let results = try await (regular, forced)

        #expect(results.0?.accessToken == "current")
        #expect(results.1?.accessToken == "forced")
        #expect(await requestCount.value == 1)
    }

    @Test
    func `refresh form encodes reserved characters`() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        try store.save(tokens: OAuthTokens(accessToken: "old", refreshToken: "r+1&x=y", expiresAt: .distantPast))
        try store.save(clientCredentials: OAuthClientCredentials(clientID: "cid+value", clientSecret: "secret&part=value"))

        let session = URLSession(configuration: Self.sessionConfiguration())
        let handlerID = UUID().uuidString
        Self.MockURLProtocol.register(handlerID: handlerID) { request in
            let body = try #require(Self.bodyString(from: request))
            #expect(body.contains("client_id=cid%2Bvalue"))
            #expect(body.contains("client_secret=secret%26part%3Dvalue"))
            #expect(body.contains("refresh_token=r%2B1%26x%3Dy"))

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            {"access_token":"new","token_type":"bearer","scope":"repo","expires_in":3600,"refresh_token":"r2"}
            """.utf8)
            return (data, response)
        }
        defer { Self.MockURLProtocol.unregister(handlerID: handlerID) }

        let refresher = OAuthTokenRefresher(tokenStore: store) { request in
            let (tagged, boxed) = Self.taggedRequest(request, handlerID: handlerID)
            _ = boxed
            return try await session.data(for: tagged)
        }

        _ = try await refresher.refreshIfNeeded(host: RepoBarAuthDefaults.githubHost)
    }

    @Test
    func `refresh failure shows helpful message`() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        try store.save(tokens: OAuthTokens(accessToken: "old", refreshToken: "r1", expiresAt: .distantPast))

        let session = URLSession(configuration: Self.sessionConfiguration())
        let handlerID = UUID().uuidString
        Self.MockURLProtocol.register(handlerID: handlerID) { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            {"error":"invalid_grant","error_description":"refresh token revoked"}
            """.utf8)
            return (data, response)
        }
        defer { Self.MockURLProtocol.unregister(handlerID: handlerID) }

        let refresher = OAuthTokenRefresher(tokenStore: store) { request in
            let (tagged, boxed) = Self.taggedRequest(request, handlerID: handlerID)
            _ = boxed
            return try await session.data(for: tagged)
        }

        do {
            _ = try await refresher.refreshIfNeeded(host: RepoBarAuthDefaults.githubHost)
            #expect(Bool(false))
        } catch let error as GitHubAPIError {
            guard case let .badStatus(code, message) = error else {
                Issue.record("Expected GitHubAPIError.badStatus, got \(error)")
                return
            }

            #expect(code == 400)
            #expect(message?.contains("Please sign in again.") == true)
            #expect(message?.contains("refresh token revoked") == true)
        }
    }

    @Test
    func `refresh failure handles malformed success response`() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        try store.save(tokens: OAuthTokens(accessToken: "old", refreshToken: "r1", expiresAt: .distantPast))

        let session = URLSession(configuration: Self.sessionConfiguration())
        let handlerID = UUID().uuidString
        Self.MockURLProtocol.register(handlerID: handlerID) { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            {"error":"invalid_grant","error_description":"refresh token revoked"}
            """.utf8)
            return (data, response)
        }
        defer { Self.MockURLProtocol.unregister(handlerID: handlerID) }

        let refresher = OAuthTokenRefresher(tokenStore: store) { request in
            let (tagged, boxed) = Self.taggedRequest(request, handlerID: handlerID)
            _ = boxed
            return try await session.data(for: tagged)
        }

        do {
            _ = try await refresher.refreshIfNeeded(host: RepoBarAuthDefaults.githubHost)
            #expect(Bool(false))
        } catch let error as GitHubAPIError {
            guard case let .badStatus(code, message) = error else {
                Issue.record("Expected GitHubAPIError.badStatus, got \(error)")
                return
            }

            #expect(code == 200)
            #expect(message?.contains("Please sign in again.") == true)
            #expect(message?.contains("refresh token revoked") == true)
        }
    }

    @Test
    func `refresh skips when refresh token missing`() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let tokens = OAuthTokens(accessToken: "tok", refreshToken: "", expiresAt: nil)
        try store.save(tokens: tokens)

        let refresher = OAuthTokenRefresher(tokenStore: store) { _ in
            throw URLError(.badServerResponse)
        }

        let refreshed = try await refresher.refreshIfNeeded(host: RepoBarAuthDefaults.githubHost)
        #expect(refreshed == tokens)
    }

    @Test
    func `account refresh does not inherit legacy client credentials`() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let accountID = "github.com#alice"
        let store = TokenStore(service: service)
        defer {
            store.clear()
            store.clear(accountID: accountID)
        }

        try store.save(tokens: OAuthTokens(accessToken: "legacy", refreshToken: "legacy-refresh", expiresAt: .distantPast))
        try store.save(clientCredentials: OAuthClientCredentials(clientID: "legacy-client", clientSecret: "legacy-secret"))
        try store.save(
            tokens: OAuthTokens(accessToken: "account", refreshToken: "account-refresh", expiresAt: .distantPast),
            accountID: accountID
        )
        let refresher = OAuthTokenRefresher(tokenStore: store) { request in
            let body = try #require(Self.bodyString(from: request))
            #expect(body.contains("client_id=legacy-client") == false)
            #expect(body.contains("client_secret=legacy-secret") == false)
            #expect(body.contains("refresh_token=account-refresh"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            {"access_token":"fresh","token_type":"bearer","scope":"repo","expires_in":3600}
            """.utf8)
            return (data, response)
        }

        let refreshed = try await refresher.refreshIfNeeded(
            host: RepoBarAuthDefaults.githubHost,
            accountID: accountID
        )

        #expect(refreshed?.accessToken == "fresh")
    }
}

private actor AsyncCallCounter {
    private(set) var value = 0

    func increment() {
        self.value += 1
    }
}

private actor AsyncStartBarrier {
    private let participants: Int
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(participants: Int) {
        self.participants = participants
    }

    func arrive() async {
        await withCheckedContinuation { continuation in
            self.continuations.append(continuation)
            guard self.continuations.count == self.participants else { return }

            let continuations = self.continuations
            self.continuations = []
            continuations.forEach { $0.resume() }
        }
    }
}

private extension OAuthTokenRefresherTests {
    static func sessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return config
    }

    // swiftlint:disable static_over_final_class
    final class MockURLProtocol: URLProtocol {
        private static let handlersLock = NSLock()
        private nonisolated(unsafe) static var handlers: [String: @Sendable (URLRequest) throws -> (Data, URLResponse)] = [:]

        static func register(
            handlerID: String,
            handler: @escaping @Sendable (URLRequest) throws -> (Data, URLResponse)
        ) {
            self.handlersLock.lock()
            self.handlers[handlerID] = handler
            self.handlersLock.unlock()
        }

        static func unregister(handlerID: String) {
            self.handlersLock.lock()
            self.handlers[handlerID] = nil
            self.handlersLock.unlock()
        }

        override class func canInit(with request: URLRequest) -> Bool {
            URLProtocol.property(forKey: "handlerID", in: request) != nil
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard
                let handlerID = URLProtocol.property(forKey: "handlerID", in: request) as? String,
                let handler = Self.handler(for: handlerID)
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                return
            }

            do {
                let (data, response) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}

        private static func handler(for handlerID: String) -> (@Sendable (URLRequest) throws -> (Data, URLResponse))? {
            self.handlersLock.lock()
            defer { handlersLock.unlock() }
            return self.handlers[handlerID]
        }
    }

    // swiftlint:enable static_over_final_class

    static func bodyString(from request: URLRequest) -> String? {
        if let body = request.httpBody, let string = String(data: body, encoding: .utf8) {
            return string
        }

        guard let stream = request.httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return String(data: data, encoding: .utf8)
    }

    static func taggedRequest(_ request: URLRequest, handlerID: String) -> (URLRequest, NSMutableURLRequest) {
        let boxed = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(handlerID, forKey: "handlerID", in: boxed)
        return (boxed as URLRequest, boxed)
    }
}
