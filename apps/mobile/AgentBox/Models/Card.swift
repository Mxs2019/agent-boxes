import Foundation

enum CardContentTrust: String, Codable, Hashable, Sendable {
    case trusted
    case untrusted

    var allowsJavaScript: Bool { self == .trusted }
}

enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct Card: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let accountID: String
    let sequence: Int64
    let title: String?
    let html: String
    let plainText: String
    let createdAt: Date
    var showAt: Date?
    var expiresAt: Date?
    var clearedAt: Date?
    var snoozedUntil: Date?
    let source: String
    let sourceName: String?
    let agentID: String?
    let contentTrust: CardContentTrust
    let metadata: [String: JSONValue]

    init(
        id: String,
        accountID: String,
        sequence: Int64,
        title: String?,
        html: String,
        plainText: String,
        createdAt: Date,
        showAt: Date? = nil,
        expiresAt: Date?,
        clearedAt: Date?,
        snoozedUntil: Date? = nil,
        source: String,
        sourceName: String?,
        agentID: String? = nil,
        contentTrust: CardContentTrust = .untrusted,
        metadata: [String: JSONValue]
    ) {
        self.id = id
        self.accountID = accountID
        self.sequence = sequence
        self.title = title
        self.html = html
        self.plainText = plainText
        self.createdAt = createdAt
        self.showAt = showAt
        self.expiresAt = expiresAt
        self.clearedAt = clearedAt
        self.snoozedUntil = snoozedUntil
        self.source = source
        self.sourceName = sourceName
        self.agentID = agentID
        self.contentTrust = contentTrust
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        accountID = try container.decode(String.self, forKey: .accountID)
        sequence = try container.decode(Int64.self, forKey: .sequence)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        html = try container.decode(String.self, forKey: .html)
        plainText = try container.decode(String.self, forKey: .plainText)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        showAt = try container.decodeIfPresent(Date.self, forKey: .showAt)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        clearedAt = try container.decodeIfPresent(Date.self, forKey: .clearedAt)
        snoozedUntil = nil
        source = try container.decode(String.self, forKey: .source)
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        agentID = try container.decodeIfPresent(String.self, forKey: .agentID)
        contentTrust = try container.decodeIfPresent(CardContentTrust.self, forKey: .contentTrust)
            ?? .untrusted
        metadata = try container.decodeIfPresent([String: JSONValue].self, forKey: .metadata) ?? [:]
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountID = "account_id"
        case sequence
        case title
        case html
        case plainText = "plain_text"
        case createdAt = "created_at"
        case showAt = "show_at"
        case expiresAt = "expires_at"
        case clearedAt = "cleared_at"
        case source
        case sourceName = "source_name"
        case agentID = "agent_id"
        case contentTrust = "content_trust"
        case metadata
    }

    func status(at date: Date = Date()) -> CardStatus {
        if !isVisible(at: date) { return .scheduled }
        if clearedAt != nil { return .cleared }
        if let snoozedUntil {
            return snoozedUntil > date ? .snoozed : .active
        }
        if let expiresAt, expiresAt <= date { return .expired }
        return .active
    }

    func isVisible(at date: Date = Date()) -> Bool {
        guard let showAt else { return true }
        return showAt <= date
    }

    func upcomingDate(at date: Date = Date()) -> Date? {
        let futureDates = [showAt, snoozedUntil]
            .compactMap { $0 }
            .filter { $0 > date }
        return futureDates.max()
    }
}

enum CardStatus: String {
    case scheduled = "Scheduled"
    case snoozed = "Snoozed"
    case active = "Active"
    case cleared = "Cleared"
    case expired = "Expired"

    var symbol: String {
        switch self {
        case .scheduled: "calendar.badge.clock"
        case .snoozed: "clock.arrow.circlepath"
        case .active: "circle.fill"
        case .cleared: "checkmark.circle.fill"
        case .expired: "clock.badge.exclamationmark.fill"
        }
    }
}

struct SyncResponse: Decodable, Sendable {
    let cards: [Card]
    let cursor: Int64
    let hasMore: Bool
    let serverTime: Date

    enum CodingKeys: String, CodingKey {
        case cards
        case cursor
        case hasMore = "has_more"
        case serverTime = "server_time"
    }
}

struct Feedback: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let cardID: String
    let agentID: String
    let agentName: String
    let comment: String
    let cardTitle: String?
    let cardHTML: String
    let createdAt: Date
    let updatedAt: Date
    let resolvedAt: Date?

    var isResolved: Bool { resolvedAt != nil }

    var snapshotCard: Card {
        Card(
            id: cardID,
            accountID: "",
            sequence: 0,
            title: cardTitle,
            html: cardHTML,
            plainText: "",
            createdAt: createdAt,
            expiresAt: nil,
            clearedAt: nil,
            source: "api",
            sourceName: agentName,
            agentID: agentID,
            contentTrust: .untrusted,
            metadata: [:]
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case cardID = "card_id"
        case agentID = "agent_id"
        case agentName = "agent_name"
        case comment
        case cardTitle = "card_title"
        case cardHTML = "card_html"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case resolvedAt = "resolved_at"
    }
}

enum CardDateCoding {
    private static let fractional = ISO8601DateFormatter()
    private static let standard = ISO8601DateFormatter()

    static func configure() {
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        standard.formatOptions = [.withInternetDateTime]
    }

    static func parse(_ value: String) -> Date? {
        fractional.date(from: value) ?? standard.date(from: value)
    }

    static func string(from date: Date) -> String {
        fractional.string(from: date)
    }

    static var decodingStrategy: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = parse(value) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "The server returned an invalid ISO 8601 date."
                )
            }
            return date
        }
    }
}
