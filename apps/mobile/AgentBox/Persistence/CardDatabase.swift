import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DatabaseError: LocalizedError {
    case open(String)
    case statement(String)
    case execution(String)

    var errorDescription: String? {
        switch self {
        case let .open(message): "The local card database could not open: \(message)"
        case let .statement(message): "The local card database rejected a statement: \(message)"
        case let .execution(message): "The local card database operation failed: \(message)"
        }
    }
}

enum PendingActionType: String, Sendable {
    case clear
    case restore
}

struct PendingAction: Sendable {
    let rowID: Int64
    let cardID: String
    let type: PendingActionType
}

actor CardDatabase {
    private var connection: OpaquePointer?

    init(url: URL? = nil) throws {
        CardDateCoding.configure()
        let databaseURL = try url ?? Self.defaultDatabaseURL()
        var opened: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &opened,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            if let opened { sqlite3_close(opened) }
            throw DatabaseError.open(message)
        }
        do {
            try Self.execute("PRAGMA foreign_keys = ON;", on: opened)
            try Self.execute("PRAGMA journal_mode = WAL;", on: opened)
            try Self.migrate(opened)
            connection = opened
        } catch {
            sqlite3_close(opened)
            throw error
        }
    }

    deinit {
        if let connection { sqlite3_close(connection) }
    }

    func allCards() throws -> [Card] {
        try queryCards(
            """
            SELECT id, account_id, sequence, title, html, plain_text, created_at, expires_at,
                   cleared_at, source, source_name, metadata_json, content_trust, agent_id,
                   show_at, snoozed_until
            FROM cards
            ORDER BY created_at DESC
            """
        )
    }

    func search(_ query: String) throws -> [Card] {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .compactMap { word -> String? in
                let cleaned = String(word.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
                return cleaned.isEmpty ? nil : "\(cleaned)*"
            }
        guard !terms.isEmpty else { return [] }

        return try queryCards(
            """
            SELECT cards.id, cards.account_id, cards.sequence, cards.title, cards.html,
                   cards.plain_text, cards.created_at, cards.expires_at, cards.cleared_at,
                   cards.source, cards.source_name, cards.metadata_json,
                   cards.content_trust, cards.agent_id, cards.show_at,
                   cards.snoozed_until
            FROM card_search
            JOIN cards ON cards.id = card_search.card_id
            WHERE card_search MATCH ?1
              AND (cards.show_at IS NULL OR cards.show_at <= ?2)
            ORDER BY cards.created_at DESC
            LIMIT 100
            """,
            bindings: [terms.joined(separator: " AND "), CardDateCoding.string(from: Date())]
        )
    }

    func upsert(_ cards: [Card]) throws {
        guard !cards.isEmpty else { return }
        try execute("BEGIN IMMEDIATE;")
        do {
            for card in cards { try upsert(card) }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func clearLocally(cardID: String, at date: Date) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            let statement = try prepare(
                "UPDATE cards SET cleared_at = COALESCE(cleared_at, ?1) WHERE id = ?2"
            )
            defer { sqlite3_finalize(statement) }
            bindText(statement, index: 1, value: CardDateCoding.string(from: date))
            bindText(statement, index: 2, value: cardID)
            try stepDone(statement)

            try replacePendingCardAction(cardID: cardID, type: .clear, at: date)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func clearAllLocally(cardIDs: [String], at date: Date) throws {
        guard !cardIDs.isEmpty else { return }
        try execute("BEGIN IMMEDIATE;")
        do {
            for cardID in cardIDs {
                do {
                    let statement = try prepare(
                        "UPDATE cards SET cleared_at = COALESCE(cleared_at, ?1) WHERE id = ?2"
                    )
                    defer { sqlite3_finalize(statement) }
                    bindText(statement, index: 1, value: CardDateCoding.string(from: date))
                    bindText(statement, index: 2, value: cardID)
                    try stepDone(statement)
                }
                try replacePendingCardAction(cardID: cardID, type: .clear, at: date)
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func restoreLocally(cardID: String, at date: Date) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            let statement = try prepare("UPDATE cards SET cleared_at = NULL WHERE id = ?1")
            defer { sqlite3_finalize(statement) }
            bindText(statement, index: 1, value: cardID)
            try stepDone(statement)

            try replacePendingCardAction(cardID: cardID, type: .restore, at: date)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func restoreToDeckLocally(cardID: String, at date: Date) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            let statement = try prepare(
                """
                UPDATE cards
                SET cleared_at = NULL, show_at = NULL, snoozed_until = ?1
                WHERE id = ?2
                """
            )
            defer { sqlite3_finalize(statement) }
            bindText(statement, index: 1, value: CardDateCoding.string(from: date))
            bindText(statement, index: 2, value: cardID)
            try stepDone(statement)

            try replacePendingCardAction(cardID: cardID, type: .restore, at: date)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func snoozeLocally(cardID: String, until date: Date?) throws {
        let statement = try prepare("UPDATE cards SET snoozed_until = ?1 WHERE id = ?2")
        defer { sqlite3_finalize(statement) }
        bindText(statement, index: 1, value: date.map(CardDateCoding.string))
        bindText(statement, index: 2, value: cardID)
        try stepDone(statement)
    }

    private func replacePendingCardAction(
        cardID: String,
        type: PendingActionType,
        at date: Date
    ) throws {
        let delete = try prepare(
            "DELETE FROM pending_actions WHERE card_id = ?1 AND type IN ('clear', 'restore')"
        )
        defer { sqlite3_finalize(delete) }
        bindText(delete, index: 1, value: cardID)
        try stepDone(delete)

        let action = try prepare(
            "INSERT INTO pending_actions (type, card_id, created_at) VALUES (?1, ?2, ?3)"
        )
        defer { sqlite3_finalize(action) }
        bindText(action, index: 1, value: type.rawValue)
        bindText(action, index: 2, value: cardID)
        bindText(action, index: 3, value: CardDateCoding.string(from: date))
        try stepDone(action)
    }

    func resetDeckForTesting() throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try execute(
                """
                UPDATE cards
                SET cleared_at = NULL, show_at = NULL, expires_at = NULL, snoozed_until = NULL;
                DELETE FROM pending_actions WHERE type IN ('clear', 'restore');
                """
            )
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func pendingActions() throws -> [PendingAction] {
        let statement = try prepare(
            "SELECT id, card_id, type FROM pending_actions ORDER BY id ASC"
        )
        defer { sqlite3_finalize(statement) }
        var actions: [PendingAction] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            actions.append(
                PendingAction(
                    rowID: sqlite3_column_int64(statement, 0),
                    cardID: text(statement, column: 1) ?? "",
                    type: PendingActionType(rawValue: text(statement, column: 2) ?? "") ?? .clear
                )
            )
        }
        return actions
    }

    func removePendingAction(rowID: Int64) throws {
        let statement = try prepare("DELETE FROM pending_actions WHERE id = ?1")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, rowID)
        try stepDone(statement)
    }

    func cursor() throws -> Int64 {
        Int64(try stateValue(for: "sync_cursor") ?? "0") ?? 0
    }

    func setCursor(_ cursor: Int64) throws {
        try setStateValue(String(cursor), for: "sync_cursor")
    }

    func lastSuccessfulSync() throws -> Date? {
        guard let value = try stateValue(for: "last_successful_sync") else { return nil }
        return CardDateCoding.parse(value)
    }

    func setLastSuccessfulSync(_ date: Date) throws {
        try setStateValue(CardDateCoding.string(from: date), for: "last_successful_sync")
    }

    func removeAllData() throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try execute(
                """
                DELETE FROM card_search;
                DELETE FROM pending_actions;
                DELETE FROM cards;
                DELETE FROM app_state;
                """
            )
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private static func defaultDatabaseURL() throws -> URL {
        let manager = FileManager.default
        let directory = try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("AgentBox", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("cards.sqlite")
    }

    private static func migrate(_ connection: OpaquePointer) throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS cards (
                id TEXT PRIMARY KEY,
                account_id TEXT NOT NULL,
                sequence INTEGER NOT NULL,
                title TEXT,
                html TEXT NOT NULL,
                plain_text TEXT NOT NULL,
                created_at TEXT NOT NULL,
                show_at TEXT,
                expires_at TEXT,
                cleared_at TEXT,
                source TEXT NOT NULL,
                source_name TEXT,
                metadata_json TEXT NOT NULL DEFAULT '{}'
            );
            CREATE INDEX IF NOT EXISTS cards_active
                ON cards(cleared_at, expires_at, sequence);
            CREATE INDEX IF NOT EXISTS cards_created
                ON cards(created_at DESC);
            CREATE TABLE IF NOT EXISTS app_state (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS pending_actions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                type TEXT NOT NULL,
                card_id TEXT NOT NULL,
                created_at TEXT NOT NULL,
                UNIQUE(type, card_id)
            );
            CREATE VIRTUAL TABLE IF NOT EXISTS card_search USING fts5(
                card_id UNINDEXED,
                title,
                plain_text,
                source_name,
                tokenize = 'unicode61'
            );
            """,
            on: connection
        )
        if !columnExists("content_trust", in: "cards", connection: connection) {
            try execute(
                "ALTER TABLE cards ADD COLUMN content_trust TEXT NOT NULL DEFAULT 'untrusted';",
                on: connection
            )
        }
        if !columnExists("agent_id", in: "cards", connection: connection) {
            try execute("ALTER TABLE cards ADD COLUMN agent_id TEXT;", on: connection)
        }
        if !columnExists("show_at", in: "cards", connection: connection) {
            try execute("ALTER TABLE cards ADD COLUMN show_at TEXT;", on: connection)
        }
        if !columnExists("snoozed_until", in: "cards", connection: connection) {
            try execute("ALTER TABLE cards ADD COLUMN snoozed_until TEXT;", on: connection)
        }
        try execute(
            "CREATE INDEX IF NOT EXISTS cards_visibility ON cards(show_at, cleared_at, expires_at, sequence);",
            on: connection
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS cards_snooze ON cards(snoozed_until, cleared_at, sequence);",
            on: connection
        )
    }

    private func upsert(_ card: Card) throws {
        let metadata = String(
            data: try JSONEncoder().encode(card.metadata),
            encoding: .utf8
        ) ?? "{}"
        let statement = try prepare(
            """
            INSERT INTO cards (
                id, account_id, sequence, title, html, plain_text, created_at, expires_at,
                cleared_at, source, source_name, metadata_json, content_trust, agent_id, show_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)
            ON CONFLICT(id) DO UPDATE SET
                account_id = excluded.account_id,
                sequence = excluded.sequence,
                title = excluded.title,
                html = excluded.html,
                plain_text = excluded.plain_text,
                created_at = excluded.created_at,
                expires_at = excluded.expires_at,
                cleared_at = CASE
                    WHEN EXISTS (
                        SELECT 1 FROM pending_actions
                        WHERE card_id = excluded.id AND type = 'clear'
                    ) THEN cards.cleared_at
                    WHEN EXISTS (
                        SELECT 1 FROM pending_actions
                        WHERE card_id = excluded.id AND type = 'restore'
                    ) THEN NULL
                    ELSE excluded.cleared_at
                END,
                source = excluded.source,
                source_name = excluded.source_name,
                metadata_json = excluded.metadata_json,
                content_trust = excluded.content_trust,
                agent_id = excluded.agent_id,
                show_at = CASE
                    WHEN EXISTS (
                        SELECT 1 FROM pending_actions
                        WHERE card_id = excluded.id AND type = 'restore'
                    ) THEN NULL
                    ELSE excluded.show_at
                END
            """
        )
        defer { sqlite3_finalize(statement) }
        bindText(statement, index: 1, value: card.id)
        bindText(statement, index: 2, value: card.accountID)
        sqlite3_bind_int64(statement, 3, card.sequence)
        bindText(statement, index: 4, value: card.title)
        bindText(statement, index: 5, value: card.html)
        bindText(statement, index: 6, value: card.plainText)
        bindText(statement, index: 7, value: CardDateCoding.string(from: card.createdAt))
        bindText(statement, index: 8, value: card.expiresAt.map(CardDateCoding.string))
        bindText(statement, index: 9, value: card.clearedAt.map(CardDateCoding.string))
        bindText(statement, index: 10, value: card.source)
        bindText(statement, index: 11, value: card.sourceName)
        bindText(statement, index: 12, value: metadata)
        bindText(statement, index: 13, value: card.contentTrust.rawValue)
        bindText(statement, index: 14, value: card.agentID)
        bindText(statement, index: 15, value: card.showAt.map(CardDateCoding.string))
        try stepDone(statement)

        let deleteSearch = try prepare("DELETE FROM card_search WHERE card_id = ?1")
        bindText(deleteSearch, index: 1, value: card.id)
        try stepDone(deleteSearch)
        sqlite3_finalize(deleteSearch)

        let insertSearch = try prepare(
            "INSERT INTO card_search (card_id, title, plain_text, source_name) VALUES (?1, ?2, ?3, ?4)"
        )
        defer { sqlite3_finalize(insertSearch) }
        bindText(insertSearch, index: 1, value: card.id)
        bindText(insertSearch, index: 2, value: card.title)
        bindText(insertSearch, index: 3, value: card.plainText)
        bindText(insertSearch, index: 4, value: card.sourceName)
        try stepDone(insertSearch)
    }

    private func queryCards(_ sql: String, bindings: [String] = []) throws -> [Card] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() {
            bindText(statement, index: Int32(offset + 1), value: value)
        }
        var cards: [Card] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            cards.append(try readCard(statement))
        }
        return cards
    }

    private func readCard(_ statement: OpaquePointer) throws -> Card {
        let metadataData = Data((text(statement, column: 11) ?? "{}").utf8)
        let metadata = (try? JSONDecoder().decode([String: JSONValue].self, from: metadataData)) ?? [:]
        return Card(
            id: text(statement, column: 0) ?? "",
            accountID: text(statement, column: 1) ?? "",
            sequence: sqlite3_column_int64(statement, 2),
            title: text(statement, column: 3),
            html: text(statement, column: 4) ?? "",
            plainText: text(statement, column: 5) ?? "",
            createdAt: CardDateCoding.parse(text(statement, column: 6) ?? "") ?? .distantPast,
            showAt: text(statement, column: 14).flatMap(CardDateCoding.parse),
            expiresAt: text(statement, column: 7).flatMap(CardDateCoding.parse),
            clearedAt: text(statement, column: 8).flatMap(CardDateCoding.parse),
            snoozedUntil: text(statement, column: 15).flatMap(CardDateCoding.parse),
            source: text(statement, column: 9) ?? "api",
            sourceName: text(statement, column: 10),
            agentID: text(statement, column: 13),
            contentTrust: CardContentTrust(rawValue: text(statement, column: 12) ?? "")
                ?? .untrusted,
            metadata: metadata
        )
    }

    private static func columnExists(
        _ column: String,
        in table: String,
        connection: OpaquePointer
    ) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "PRAGMA table_info(\(table))", -1, &statement, nil)
            == SQLITE_OK,
            let statement
        else { return false }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let name = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: name) == column { return true }
        }
        return false
    }

    private func stateValue(for key: String) throws -> String? {
        let statement = try prepare("SELECT value FROM app_state WHERE key = ?1")
        defer { sqlite3_finalize(statement) }
        bindText(statement, index: 1, value: key)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return text(statement, column: 0)
    }

    private func setStateValue(_ value: String, for key: String) throws {
        let statement = try prepare(
            "INSERT INTO app_state (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
        )
        defer { sqlite3_finalize(statement) }
        bindText(statement, index: 1, value: key)
        bindText(statement, index: 2, value: value)
        try stepDone(statement)
    }

    private func execute(_ sql: String) throws {
        guard let connection else {
            throw DatabaseError.execution("The SQLite connection is not available.")
        }
        try Self.execute(sql, on: connection)
    }

    private static func execute(_ sql: String, on connection: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(connection, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(connection))
            sqlite3_free(errorMessage)
            throw DatabaseError.execution(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DatabaseError.statement(lastError())
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.execution(lastError())
        }
    }

    private func bindText(_ statement: OpaquePointer, index: Int32, value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, column)
        else { return nil }
        return String(cString: value)
    }

    private func lastError() -> String {
        connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
    }
}
