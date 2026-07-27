import Foundation
@testable import RepoBarCore
import Testing

struct OAuthLoginFlowTests {
    @Test
    @MainActor
    func `login persists tokens and client credentials`() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let session = URLSession(configuration: Self.sessionConfiguration())
        let handlerID = UUID().uuidString
        Self.MockURLProtocol.register(handlerID: handlerID) { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString.contains("/login/oauth/access_token") == true)
            let body = try #require(Self.bodyString(from: request))
            #expect(body.contains("client_id=cid"))
            #expect(body.contains("client_secret=csecret"))
            #expect(body.contains("grant_type=authorization_code"))
            #expect(body.contains("code=code-123"))
            #expect(body.contains("code_verifier="))

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            {"access_token":"tok","token_type":"bearer","scope":"repo","expires_in":3600,"refresh_token":"ref"}
            """.utf8)
            return (data, response)
        }
        defer { Self.MockURLProtocol.unregister(handlerID: handlerID) }

        let fakeRedirectURL = try #require(URL(string: "http://127.0.0.1:12345/callback"))
        let server = FakeLoopbackServer(
            redirectURL: fakeRedirectURL,
            result: (code: "code-123", state: "state-123")
        )
        let host = try #require(URL(string: "https://example.com"))

        let flow = OAuthLoginFlow(
            tokenStore: store,
            openURL: { url in
                let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
                let state = query.first(where: { $0.name == "state" })?.value
                let redirect = query.first(where: { $0.name == "redirect_uri" })?.value
                guard state == "state-123" else { throw URLError(.badServerResponse) }
                guard redirect == fakeRedirectURL.absoluteString else { throw URLError(.badURL) }

                #expect(query.contains { $0.name == "scope" } == false)
            },
            dataProvider: { request in
                let (tagged, boxed) = Self.taggedRequest(request, handlerID: handlerID)
                _ = boxed
                return try await session.data(for: tagged)
            },
            makeLoopbackServer: { _ in server },
            stateProvider: { "state-123" }
        )

        let tokens = try await flow.login(
            clientID: "cid",
            clientSecret: "csecret",
            host: host,
            loopbackPort: 12345,
            timeout: 2
        )
        #expect(tokens.accessToken == "tok")
        #expect(tokens.refreshToken == "ref")
        #expect(tokens.expiresAt != nil)

        #expect(try store.load()?.accessToken == "tok")
        #expect(try store.loadClientCredentials()?.clientID == "cid")
        #expect(try store.loadClientCredentials()?.clientSecret == "csecret")
        #expect(server.stopCallCount == 1)
    }

    @Test
    @MainActor
    func `login form encodes reserved characters`() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let session = URLSession(configuration: Self.sessionConfiguration())
        let handlerID = UUID().uuidString
        Self.MockURLProtocol.register(handlerID: handlerID) { request in
            let body = try #require(Self.bodyString(from: request))
            #expect(body.contains("client_id=cid%2Bvalue"))
            #expect(body.contains("client_secret=secret%26part%3Dvalue"))
            #expect(body.contains("code=code%2B1%262"))
            #expect(body.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A12345%2Fcallback%3Fspace%3Da%2520b"))

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            {"access_token":"tok","token_type":"bearer","expires_in":3600,"refresh_token":"ref"}
            """.utf8)
            return (data, response)
        }
        defer { Self.MockURLProtocol.unregister(handlerID: handlerID) }

        let fakeRedirectURL = try #require(URL(string: "http://127.0.0.1:12345/callback?space=a b"))
        let server = FakeLoopbackServer(
            redirectURL: fakeRedirectURL,
            result: (code: "code+1&2", state: "state-123")
        )
        let host = try #require(URL(string: "https://example.com"))

        let flow = OAuthLoginFlow(
            tokenStore: store,
            openURL: { _ in },
            dataProvider: { request in
                let (tagged, boxed) = Self.taggedRequest(request, handlerID: handlerID)
                _ = boxed
                return try await session.data(for: tagged)
            },
            makeLoopbackServer: { _ in server },
            stateProvider: { "state-123" }
        )

        _ = try await flow.login(
            clientID: "cid+value",
            clientSecret: "secret&part=value",
            host: host,
            loopbackPort: 12345,
            timeout: 2
        )
    }

    @Test
    @MainActor
    func `login stops loopback server when opening browser fails`() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let fakeRedirectURL = try #require(URL(string: "http://127.0.0.1:12345/callback"))
        let server = FakeLoopbackServer(
            redirectURL: fakeRedirectURL,
            result: (code: "code-123", state: "state-123")
        )
        let host = try #require(URL(string: "https://example.com"))
        let flow = OAuthLoginFlow(
            tokenStore: store,
            openURL: { _ in throw URLError(.cannotOpenFile) },
            dataProvider: { _ in throw URLError(.badServerResponse) },
            makeLoopbackServer: { _ in server },
            stateProvider: { "state-123" }
        )

        do {
            _ = try await flow.login(clientID: "cid", clientSecret: "csecret", host: host, loopbackPort: 12345, timeout: 2)
            Issue.record("Expected login to fail")
        } catch {
            #expect((error as? URLError)?.code == .cannotOpenFile)
        }

        #expect(server.stopCallCount == 1)
    }

    @Test
    @MainActor
    func `login includes explicit scope when requested`() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let session = URLSession(configuration: Self.sessionConfiguration())
        let handlerID = UUID().uuidString
        Self.MockURLProtocol.register(handlerID: handlerID) { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            {"access_token":"tok","token_type":"bearer","expires_in":3600,"refresh_token":"ref"}
            """.utf8)
            return (data, response)
        }
        defer { Self.MockURLProtocol.unregister(handlerID: handlerID) }

        let fakeRedirectURL = try #require(URL(string: "http://127.0.0.1:12345/callback"))
        let server = FakeLoopbackServer(
            redirectURL: fakeRedirectURL,
            result: (code: "code-123", state: "state-123")
        )
        let host = try #require(URL(string: "https://example.com"))

        let flow = OAuthLoginFlow(
            tokenStore: store,
            openURL: { url in
                let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
                #expect(query.first(where: { $0.name == "scope" })?.value == "repo read:org")
            },
            dataProvider: { request in
                let (tagged, boxed) = Self.taggedRequest(request, handlerID: handlerID)
                _ = boxed
                return try await session.data(for: tagged)
            },
            makeLoopbackServer: { _ in server },
            stateProvider: { "state-123" }
        )

        _ = try await flow.login(
            clientID: "cid",
            clientSecret: "csecret",
            host: host,
            loopbackPort: 12345,
            scope: "repo read:org",
            timeout: 2
        )
    }

    @Test
    @MainActor
    func `normalize host requires HTTPS`() throws {
        do {
            _ = try OAuthLoginFlow.normalizeHost(#require(URL(string: "http://github.com")))
            Issue.record("Expected invalidHost")
        } catch {
            guard let gh = error as? GitHubAPIError, case .invalidHost = gh else {
                Issue.record("Expected GitHubAPIError.invalidHost, got \(error)")
                return
            }
        }

        do {
            _ = try OAuthLoginFlow.normalizeHost(#require(URL(string: "github.com")))
            Issue.record("Expected invalidHost")
        } catch {
            guard let gh = error as? GitHubAPIError, case .invalidHost = gh else {
                Issue.record("Expected GitHubAPIError.invalidHost, got \(error)")
                return
            }
        }

        let cleaned = try OAuthLoginFlow.normalizeHost(#require(URL(string: "https://github.com/path?q=1#frag")))
        #expect(cleaned.absoluteString == "https://github.com")
    }
}

private extension OAuthLoginFlowTests {
    static func sessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return config
    }

    final class FakeLoopbackServer: LoopbackServing {
        private let redirectURL: URL
        private let result: (code: String, state: String)
        private(set) var stopCallCount = 0

        init(redirectURL: URL, result: (code: String, state: String)) {
            self.redirectURL = redirectURL
            self.result = result
        }

        func start() throws -> URL {
            self.redirectURL
        }

        func waitForCallback(timeout _: TimeInterval) async throws -> (code: String, state: String) {
            self.result
        }

        func stop() {
            self.stopCallCount += 1
        }
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
