import Foundation

enum APNSEnvironment: String, Encodable, Sendable {
    case development
    case production

    static var current: Self {
#if DEBUG
        .development
#else
        .production
#endif
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The Agent Box service returned an invalid response."
        case let .server(status, message): "The Agent Box service returned \(status): \(message)"
        }
    }
}

struct APIClient: Sendable {
    let baseURL: URL
    let accountKey: String

    static func createAccount(baseURL: URL) async throws -> String {
        let url = baseURL.appendingPathComponent("v1/accounts")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        let data = try await send(request)
        return try JSONDecoder().decode(AccountCreationResponse.self, from: data).accountKey
    }

    func sync(after cursor: Int64, limit: Int = 200) async throws -> SyncResponse {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/sync"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "after", value: String(cursor)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = components?.url else { throw APIError.invalidResponse }
        let data = try await sendAuthenticated(URLRequest(url: url))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = CardDateCoding.decodingStrategy
        return try decoder.decode(SyncResponse.self, from: data)
    }

    func clear(cardID: String) async throws {
        let url = baseURL
            .appendingPathComponent("v1/cards")
            .appendingPathComponent(cardID)
            .appendingPathComponent("clear")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        _ = try await sendAuthenticated(request)
    }

    func restore(cardID: String) async throws {
        let url = baseURL
            .appendingPathComponent("v1/cards")
            .appendingPathComponent(cardID)
            .appendingPathComponent("restore")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        _ = try await sendAuthenticated(request)
    }

    func listFeedback() async throws -> [Feedback] {
        let url = baseURL.appendingPathComponent("v1/feedback")
        let data = try await sendAuthenticated(URLRequest(url: url))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = CardDateCoding.decodingStrategy
        return try decoder.decode(FeedbackListResponse.self, from: data).feedback
    }

    func createFeedback(cardID: String, comment: String) async throws -> Feedback {
        let url = baseURL
            .appendingPathComponent("v1/cards")
            .appendingPathComponent(cardID)
            .appendingPathComponent("feedback")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(FeedbackRequest(comment: comment))
        return try decodeFeedback(try await sendAuthenticated(request))
    }

    func updateFeedback(id: String, comment: String) async throws -> Feedback {
        let url = baseURL.appendingPathComponent("v1/feedback").appendingPathComponent(id)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(FeedbackRequest(comment: comment))
        return try decodeFeedback(try await sendAuthenticated(request))
    }

    func deleteFeedback(id: String) async throws {
        let url = baseURL.appendingPathComponent("v1/feedback").appendingPathComponent(id)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try await sendAuthenticated(request)
    }

    func registerDevice(
        id: String,
        apnsToken: String,
        environment: APNSEnvironment
    ) async throws {
        let url = baseURL.appendingPathComponent("v1/devices")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            DeviceRegistration(id: id, apnsToken: apnsToken, apnsEnvironment: environment)
        )
        _ = try await sendAuthenticated(request)
    }

    func unregisterDevice(id: String) async throws {
        let url = baseURL.appendingPathComponent("v1/devices").appendingPathComponent(id)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try await sendAuthenticated(request)
    }

    func deleteAccount() async throws {
        let url = baseURL.appendingPathComponent("v1/account")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try await sendAuthenticated(request)
    }

    func resetOnboarding() async throws {
        let url = baseURL.appendingPathComponent("v1/onboarding/reset")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        _ = try await sendAuthenticated(request)
    }

    func listAgents() async throws -> [Agent] {
        let url = baseURL.appendingPathComponent("v1/agents")
        let data = try await sendAuthenticated(URLRequest(url: url))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = CardDateCoding.decodingStrategy
        return try decoder.decode(AgentListResponse.self, from: data).agents
    }

    func createAgent(name: String) async throws -> AgentCredential {
        let url = baseURL.appendingPathComponent("v1/agents")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(NameRequest(name: name))
        let data = try await sendAuthenticated(request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = CardDateCoding.decodingStrategy
        let response = try decoder.decode(AgentCreationResponse.self, from: data)
        return AgentCredential(agent: response.agent, agentKey: response.agentKey)
    }

    func revealAgentKey(id: String) async throws -> String {
        let url = baseURL
            .appendingPathComponent("v1/agents")
            .appendingPathComponent(id)
            .appendingPathComponent("key")
        let data = try await sendAuthenticated(URLRequest(url: url))
        return try JSONDecoder().decode(AgentKeyResponse.self, from: data).agentKey
    }

    func replaceAgentKey(id: String) async throws -> String {
        let url = baseURL
            .appendingPathComponent("v1/agents")
            .appendingPathComponent(id)
            .appendingPathComponent("key")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let data = try await sendAuthenticated(request)
        return try JSONDecoder().decode(AgentKeyResponse.self, from: data).agentKey
    }

    func renameAgent(id: String, name: String) async throws -> Agent {
        let url = baseURL.appendingPathComponent("v1/agents").appendingPathComponent(id)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(NameRequest(name: name))
        let data = try await sendAuthenticated(request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = CardDateCoding.decodingStrategy
        return try decoder.decode(AgentResponse.self, from: data).agent
    }

    func revokeAgent(id: String) async throws {
        let url = baseURL.appendingPathComponent("v1/agents").appendingPathComponent(id)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try await sendAuthenticated(request)
    }

    func listInboxes() async throws -> [Inbox] {
        let url = baseURL.appendingPathComponent("v1/inboxes")
        let data = try await sendAuthenticated(URLRequest(url: url))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = CardDateCoding.decodingStrategy
        return try decoder.decode(InboxListResponse.self, from: data).inboxes
    }

    func createInbox(name: String) async throws -> Inbox {
        let url = baseURL.appendingPathComponent("v1/inboxes")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(NameRequest(name: name))
        let data = try await sendAuthenticated(request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = CardDateCoding.decodingStrategy
        return try decoder.decode(InboxCreationResponse.self, from: data).inbox
    }

    func renameInbox(id: String, name: String) async throws -> Inbox {
        let url = baseURL.appendingPathComponent("v1/inboxes").appendingPathComponent(id)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(NameRequest(name: name))
        let data = try await sendAuthenticated(request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = CardDateCoding.decodingStrategy
        return try decoder.decode(InboxCreationResponse.self, from: data).inbox
    }

    func revokeInbox(id: String) async throws {
        let url = baseURL.appendingPathComponent("v1/inboxes").appendingPathComponent(id)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try await sendAuthenticated(request)
    }

    private func decodeFeedback(_ data: Data) throws -> Feedback {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = CardDateCoding.decodingStrategy
        return try decoder.decode(FeedbackResponse.self, from: data).feedback
    }

    private func sendAuthenticated(_ original: URLRequest) async throws -> Data {
        var request = original
        request.setValue("Bearer \(accountKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        return try await Self.send(request)
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard 200 ..< 300 ~= response.statusCode else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data).error.message)
                ?? String(data: data, encoding: .utf8)
                ?? "Unknown service error"
            throw APIError.server(response.statusCode, message)
        }
        return data
    }
}

struct Agent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let keyHint: String
    let createdAt: Date
    let lastUsedAt: Date?
    let revokedAt: Date?

    var isRevoked: Bool { revokedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case keyHint = "key_hint"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
        case revokedAt = "revoked_at"
    }
}

struct AgentCredential: Sendable {
    let agent: Agent
    let agentKey: String
}

struct Inbox: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let emailAddress: String
    let createdAt: Date
    let revokedAt: Date?

    var isRevoked: Bool { revokedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case emailAddress = "email_address"
        case createdAt = "created_at"
        case revokedAt = "revoked_at"
    }
}

private struct AccountCreationResponse: Decodable {
    let accountKey: String

    enum CodingKeys: String, CodingKey {
        case accountKey = "account_key"
    }
}

private struct AgentListResponse: Decodable {
    let agents: [Agent]
}

private struct NameRequest: Encodable {
    let name: String
}

private struct AgentCreationResponse: Decodable {
    let agent: Agent
    let agentKey: String

    enum CodingKeys: String, CodingKey {
        case agent
        case agentKey = "agent_key"
    }
}

private struct AgentKeyResponse: Decodable {
    let agentKey: String

    enum CodingKeys: String, CodingKey {
        case agentKey = "agent_key"
    }
}

private struct AgentResponse: Decodable {
    let agent: Agent
}

private struct InboxListResponse: Decodable {
    let inboxes: [Inbox]
}

private struct InboxCreationResponse: Decodable {
    let inbox: Inbox
}

private struct DeviceRegistration: Encodable {
    let id: String
    let apnsToken: String
    let apnsEnvironment: APNSEnvironment

    enum CodingKeys: String, CodingKey {
        case id
        case apnsToken = "apns_token"
        case apnsEnvironment = "apns_environment"
    }
}

private struct FeedbackRequest: Encodable {
    let comment: String
}

private struct FeedbackResponse: Decodable {
    let feedback: Feedback
}

private struct FeedbackListResponse: Decodable {
    let feedback: [Feedback]
}

private struct ErrorResponse: Decodable {
    let error: ServiceError
}

private struct ServiceError: Decodable {
    let message: String
}
