import Foundation

struct CardSearchMatch: Sendable {
    let titleRanges: [NSRange]
    let bodyRanges: [NSRange]
    let sourceRanges: [NSRange]
}

struct CardSearchResult: Identifiable, Sendable {
    let card: Card
    let score: Int
    let match: CardSearchMatch

    var id: String { card.id }
}

struct CardSearchTaskID: Hashable {
    let scope: String
    let query: String
    let cardIDs: [String]
}

actor CardSearchIndex {
    private static let resultTarget = 50
    private static let tierCount = 4

    private var documents: [String: CardSearchDocument] = [:]
    private var preparedCardIDs: [String] = []
    private var preparedDay: Date?
    private var tierVocabularies: [[CardSearchVocabularyToken]] = Array(
        repeating: [],
        count: tierCount
    )

    func prepare(_ cards: [Card]) {
        _ = preparedDocuments(for: cards, referenceDate: Date())
    }

    func search(_ query: String, in cards: [Card], limit: Int = 200) -> [CardSearchResult] {
        let parsedQuery = CardSearchQuery(query)
        guard !parsedQuery.terms.isEmpty else { return [] }

        let referenceDate = Date()
        let activeDocuments = preparedDocuments(for: cards, referenceDate: referenceDate)
        var tierDocuments = Array(
            repeating: [(card: Card, document: CardSearchDocument)](),
            count: Self.tierCount
        )
        for item in activeDocuments {
            let tier = CardSearchRecency.tier(
                for: item.card.createdAt,
                relativeTo: referenceDate
            )
            tierDocuments[tier].append(item)
        }

        var matches: [CardSearchDocumentMatch] = []
        matches.reserveCapacity(min(cards.count, limit))
        let resultTarget = min(limit, Self.resultTarget)
        var searchedDocumentCount = 0
        var lastSearchedTier = tierDocuments.indices.last ?? 0
        for tier in tierDocuments.indices {
            let termPlans = parsedQuery.terms.map {
                CardSearchTermPlan(term: $0, vocabulary: tierVocabularies[tier])
            }
            for item in tierDocuments[tier] {
                if searchedDocumentCount.isMultiple(of: 64), Task.isCancelled { return [] }
                searchedDocumentCount += 1
                if let match = item.document.match(
                    for: parsedQuery,
                    termPlans: termPlans,
                    card: item.card,
                    referenceDate: referenceDate
                ) {
                    matches.append(match)
                }
            }
            if matches.count >= resultTarget {
                lastSearchedTier = tier
                break
            }
        }

        if lastSearchedTier < tierDocuments.count - 1 {
            for tier in (lastSearchedTier + 1)..<tierDocuments.count {
                let strongDocuments = tierDocuments[tier].filter {
                    $0.document.hasStrongMatch(for: parsedQuery)
                }
                var strongTokens: [String: CardSearchVocabularyToken] = [:]
                for item in strongDocuments {
                    for token in item.document.tokens where strongTokens[token.value] == nil {
                        strongTokens[token.value] = CardSearchVocabularyToken(token)
                    }
                }
                let strongVocabulary = Array(strongTokens.values)
                let termPlans = parsedQuery.terms.map {
                    CardSearchTermPlan(term: $0, vocabulary: strongVocabulary)
                }
                for item in strongDocuments {
                    if let match = item.document.match(
                        for: parsedQuery,
                        termPlans: termPlans,
                        card: item.card,
                        referenceDate: referenceDate
                    ) {
                        matches.append(match)
                    }
                }
            }
        }

        matches.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.card.createdAt != $1.card.createdAt {
                return $0.card.createdAt > $1.card.createdAt
            }
            return $0.card.sequence > $1.card.sequence
        }
        return matches.prefix(limit).map { $0.result(for: parsedQuery) }
    }

    private func preparedDocuments(
        for cards: [Card],
        referenceDate: Date
    ) -> [(card: Card, document: CardSearchDocument)] {
        let cardIDs = Set(cards.map(\.id))
        if cardIDs != Set(documents.keys) {
            documents = documents.filter { cardIDs.contains($0.key) }
        }

        var active: [(card: Card, document: CardSearchDocument)] = []
        active.reserveCapacity(cards.count)
        var changed = false
        for card in cards {
            let document: CardSearchDocument
            if let cached = documents[card.id], cached.hasSearchText(for: card) {
                document = cached
            } else {
                document = CardSearchDocument(card: card)
                documents[card.id] = document
                changed = true
            }
            active.append((card, document))
        }

        let orderedIDs = cards.map(\.id)
        let day = Calendar.autoupdatingCurrent.startOfDay(for: referenceDate)
        if changed || orderedIDs != preparedCardIDs || day != preparedDay {
            var uniqueTokens = Array(
                repeating: [String: CardSearchVocabularyToken](),
                count: Self.tierCount
            )
            for item in active {
                let tier = CardSearchRecency.tier(
                    for: item.card.createdAt,
                    relativeTo: referenceDate
                )
                for token in item.document.tokens where uniqueTokens[tier][token.value] == nil {
                    uniqueTokens[tier][token.value] = CardSearchVocabularyToken(token)
                }
            }
            tierVocabularies = uniqueTokens.map { Array($0.values) }
            preparedCardIDs = orderedIDs
            preparedDay = day
        }
        return active
    }
}

private enum CardSearchRecency {
    private static let day: TimeInterval = 86_400

    static func tier(for date: Date, relativeTo referenceDate: Date) -> Int {
        let age = max(0, referenceDate.timeIntervalSince(date))
        switch age {
        case ...(7 * day): return 0
        case ...(30 * day): return 1
        case ...(90 * day): return 2
        default: return 3
        }
    }

    static func score(for date: Date, relativeTo referenceDate: Date) -> Int {
        let ageInDays = max(0, referenceDate.timeIntervalSince(date) / day)
        switch ageInDays {
        case ...7:
            return 240 - Int(ageInDays * 8)
        case ...30:
            return 184 - Int((ageInDays - 7) * 4)
        case ...90:
            return 92 - Int(ageInDays - 30)
        default:
            return max(0, 32 - Int((ageInDays - 90) / 8))
        }
    }
}

private struct CardSearchQuery {
    let original: String
    let normalized: String
    let terms: [CardSearchTerm]

    init(_ query: String) {
        original = query.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized = Self.normalize(original)
        terms = Self.words(in: original).map(CardSearchTerm.init)
    }

    static func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }

    static func words(in value: String) -> [String] {
        var words: [String] = []
        value.enumerateSubstrings(
            in: value.startIndex..<value.endIndex,
            options: [.byWords, .substringNotRequired]
        ) { _, range, _, _ in
            let word = normalize(String(value[range]))
            if !word.isEmpty { words.append(word) }
        }
        return words
    }
}

private struct CardSearchTerm {
    let value: String
    let scalars: [UInt32]

    init(_ value: String) {
        self.value = value
        scalars = value.unicodeScalars.map(\.value)
    }
}

private struct CardSearchToken {
    let value: String
    let scalars: [UInt32]
    let range: NSRange
    let position: Int
}

private struct CardSearchVocabularyToken {
    let value: String
    let scalars: [UInt32]

    init(_ token: CardSearchToken) {
        value = token.value
        scalars = token.scalars
    }
}

private struct CardSearchTermPlan {
    let scoresByToken: [String: Int]

    init(term: CardSearchTerm, vocabulary: [CardSearchVocabularyToken]) {
        let allowedDistance = Self.allowedEditDistance(for: term.scalars.count)
        var scores: [String: Int] = [:]
        scores.reserveCapacity(vocabulary.count / 4)
        for token in vocabulary {
            let score: Int
            if token.value == term.value {
                score = 700
            } else if token.value.hasPrefix(term.value) {
                score = 590
            } else if token.value.contains(term.value) {
                score = 480
            } else if allowedDistance > 0 {
                let distance = Self.editDistance(
                    term.scalars,
                    token.scalars,
                    limit: allowedDistance
                )
                guard distance <= allowedDistance else { continue }
                score = 390 - (distance * 85)
            } else {
                continue
            }
            scores[token.value] = score
        }
        scoresByToken = scores
    }

    private static func allowedEditDistance(for length: Int) -> Int {
        switch length {
        case 0...2: 0
        case 3...5: 1
        default: 2
        }
    }

    private static func editDistance(
        _ first: [UInt32],
        _ second: [UInt32],
        limit: Int
    ) -> Int {
        guard abs(first.count - second.count) <= limit else { return limit + 1 }
        if first == second { return 0 }

        var previousPrevious = Array(0...second.count)
        var previous = previousPrevious
        for firstIndex in first.indices {
            var current = Array(repeating: 0, count: second.count + 1)
            current[0] = firstIndex + 1
            var rowMinimum = current[0]
            for secondIndex in second.indices {
                let substitution = previous[secondIndex]
                    + (first[firstIndex] == second[secondIndex] ? 0 : 1)
                current[secondIndex + 1] = min(
                    min(previous[secondIndex + 1] + 1, current[secondIndex] + 1),
                    substitution
                )
                if firstIndex > 0,
                   secondIndex > 0,
                   first[firstIndex] == second[secondIndex - 1],
                   first[firstIndex - 1] == second[secondIndex]
                {
                    current[secondIndex + 1] = min(
                        current[secondIndex + 1],
                        previousPrevious[secondIndex - 1] + 1
                    )
                }
                rowMinimum = min(rowMinimum, current[secondIndex + 1])
            }
            if rowMinimum > limit { return limit + 1 }
            previousPrevious = previous
            previous = current
        }
        return previous[second.count]
    }
}

private struct CardSearchField {
    let text: String
    let normalized: String
    let tokens: [CardSearchToken]
    let weight: Int

    init(text: String, weight: Int) {
        self.text = text
        normalized = CardSearchQuery.normalize(text)
        self.weight = weight

        var parsedTokens: [CardSearchToken] = []
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byWords, .substringNotRequired]
        ) { _, range, _, _ in
            let value = CardSearchQuery.normalize(String(text[range]))
            guard !value.isEmpty else { return }
            parsedTokens.append(
                CardSearchToken(
                    value: value,
                    scalars: value.unicodeScalars.map(\.value),
                    range: NSRange(range, in: text),
                    position: parsedTokens.count
                )
            )
        }
        tokens = parsedTokens
    }

    func bestMatch(for plan: CardSearchTermPlan) -> CardSearchCandidate? {
        var bestMatch: CardSearchCandidate?
        for token in tokens {
            guard let baseScore = plan.scoresByToken[token.value] else { continue }
            let candidate = CardSearchCandidate(
                score: baseScore + weight + max(0, 30 - token.position),
                range: token.range
            )
            if bestMatch == nil || candidate.score > bestMatch?.score ?? 0 {
                bestMatch = candidate
            }
        }
        return bestMatch
    }

    func phraseBonus(for query: CardSearchQuery) -> Int {
        guard normalized.contains(query.normalized) else { return 0 }
        if normalized == query.normalized { return 1_500 + weight }
        if normalized.hasPrefix(query.normalized) { return 1_100 + weight }
        return 800 + weight
    }

    func literalRanges(for query: CardSearchQuery) -> [NSRange] {
        var ranges: [NSRange] = []
        if !query.original.isEmpty {
            ranges.append(contentsOf: literalRanges(for: query.original, limit: 8))
        }
        for term in query.terms {
            ranges.append(contentsOf: literalRanges(for: term.value, limit: 8))
        }
        return Self.merged(ranges)
    }

    private func literalRanges(for value: String, limit: Int) -> [NSRange] {
        let source = text as NSString
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: source.length)
        while searchRange.length > 0, ranges.count < limit {
            let range = source.range(
                of: value,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                range: searchRange
            )
            guard range.location != NSNotFound else { break }
            ranges.append(range)
            let nextLocation = range.location + max(range.length, 1)
            searchRange = NSRange(location: nextLocation, length: source.length - nextLocation)
        }
        return ranges
    }

    static func merged(_ ranges: [NSRange]) -> [NSRange] {
        let sorted = ranges
            .filter { $0.location != NSNotFound && $0.length > 0 }
            .sorted {
                $0.location == $1.location ? $0.length > $1.length : $0.location < $1.location
            }
        var output: [NSRange] = []
        for range in sorted {
            guard let last = output.last else {
                output.append(range)
                continue
            }
            let lastEnd = last.location + last.length
            if range.location <= lastEnd {
                output[output.count - 1].length = max(lastEnd, range.location + range.length)
                    - last.location
            } else {
                output.append(range)
            }
        }
        return output
    }
}

private struct CardSearchCandidate {
    let score: Int
    let range: NSRange
}

private struct CardSearchDocument {
    let title: CardSearchField?
    let body: CardSearchField
    let source: CardSearchField?

    init(card: Card) {
        title = card.title.map { CardSearchField(text: $0, weight: 260) }
        body = CardSearchField(text: card.plainText, weight: 0)
        source = card.sourceName.map { CardSearchField(text: $0, weight: 140) }
    }

    var tokens: [CardSearchToken] {
        (title?.tokens ?? []) + body.tokens + (source?.tokens ?? [])
    }

    func hasSearchText(for card: Card) -> Bool {
        title?.text == card.title && body.text == card.plainText && source?.text == card.sourceName
    }

    func hasStrongMatch(for query: CardSearchQuery) -> Bool {
        [title, source].compactMap { $0 }.contains { field in
            query.terms.allSatisfy { term in
                field.tokens.contains {
                    $0.value == term.value || $0.value.hasPrefix(term.value)
                }
            }
        }
    }

    func match(
        for query: CardSearchQuery,
        termPlans: [CardSearchTermPlan],
        card: Card,
        referenceDate: Date
    ) -> CardSearchDocumentMatch? {
        let fields = [title, body, source]
        var score = (fields.compactMap { $0?.phraseBonus(for: query) }.max() ?? 0)
            + CardSearchRecency.score(for: card.createdAt, relativeTo: referenceDate)
        var titleRanges: [NSRange] = []
        var bodyRanges: [NSRange] = []
        var sourceRanges: [NSRange] = []

        for plan in termPlans {
            var best: (field: Int, candidate: CardSearchCandidate)?
            for (fieldIndex, field) in fields.enumerated() {
                guard let candidate = field?.bestMatch(for: plan) else { continue }
                if best == nil || candidate.score > best?.candidate.score ?? 0 {
                    best = (fieldIndex, candidate)
                }
            }
            guard let best else { return nil }
            score += best.candidate.score
            switch best.field {
            case 0: titleRanges.append(best.candidate.range)
            case 1: bodyRanges.append(best.candidate.range)
            default: sourceRanges.append(best.candidate.range)
            }
        }

        return CardSearchDocumentMatch(
            card: card,
            score: score,
            document: self,
            titleRanges: titleRanges,
            bodyRanges: bodyRanges,
            sourceRanges: sourceRanges
        )
    }
}

private struct CardSearchDocumentMatch {
    let card: Card
    let score: Int
    let document: CardSearchDocument
    let titleRanges: [NSRange]
    let bodyRanges: [NSRange]
    let sourceRanges: [NSRange]

    func result(for query: CardSearchQuery) -> CardSearchResult {
        var allTitleRanges = titleRanges
        var allBodyRanges = bodyRanges
        var allSourceRanges = sourceRanges
        if let title = document.title {
            allTitleRanges.append(contentsOf: title.literalRanges(for: query))
        }
        allBodyRanges.append(contentsOf: document.body.literalRanges(for: query))
        if let source = document.source {
            allSourceRanges.append(contentsOf: source.literalRanges(for: query))
        }

        return CardSearchResult(
            card: card,
            score: score,
            match: CardSearchMatch(
                titleRanges: CardSearchField.merged(allTitleRanges),
                bodyRanges: CardSearchField.merged(allBodyRanges),
                sourceRanges: CardSearchField.merged(allSourceRanges)
            )
        )
    }
}
