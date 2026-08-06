import SwiftUI

struct CardRow: View {
    let card: Card
    let searchMatch: CardSearchMatch?
    let showsBody: Bool

    init(
        card: Card,
        searchMatch: CardSearchMatch? = nil,
        showsBody: Bool = true
    ) {
        self.card = card
        self.searchMatch = searchMatch
        self.showsBody = showsBody
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                highlighted(
                    CardSearchText.presentation(
                        text: card.title ?? "Untitled",
                        ranges: searchMatch?.titleRanges ?? []
                    )
                )
            )
                .font(.headline)
                .lineLimit(1)

            if showsBody {
                Text(
                    highlighted(
                        CardSearchText.presentation(
                            text: card.plainText,
                            ranges: searchMatch?.bodyRanges ?? [],
                            usesSnippet: searchMatch != nil
                        )
                    )
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(
                highlighted(
                    CardSearchText.presentation(
                        text: card.sourceName ?? card.source.capitalized,
                        ranges: searchMatch?.sourceRanges ?? []
                    )
                )
            )
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private func highlighted(_ presentation: CardSearchText.Presentation) -> AttributedString {
        var output = AttributedString(presentation.text)
        for range in presentation.ranges {
            guard let stringRange = Range(range, in: presentation.text),
                  let lowerBound = AttributedString.Index(stringRange.lowerBound, within: output),
                  let upperBound = AttributedString.Index(stringRange.upperBound, within: output)
            else { continue }
            output[lowerBound..<upperBound].backgroundColor = Color.accentColor.opacity(0.24)
        }
        return output
    }
}

private enum CardSearchText {
    struct Presentation {
        let text: String
        let ranges: [NSRange]
    }

    static func presentation(
        text: String,
        ranges: [NSRange],
        usesSnippet: Bool = false
    ) -> Presentation {
        guard usesSnippet,
              let firstRange = ranges.first,
              let firstMatch = Range(firstRange, in: text)
        else { return Presentation(text: text, ranges: ranges) }

        let start = text.index(
            firstMatch.lowerBound,
            offsetBy: -48,
            limitedBy: text.startIndex
        ) ?? text.startIndex
        let end = text.index(
            firstMatch.upperBound,
            offsetBy: 112,
            limitedBy: text.endIndex
        ) ?? text.endIndex
        let sourceRange = NSRange(start..<end, in: text)
        let hasLeadingEllipsis = start != text.startIndex
        let prefix = hasLeadingEllipsis ? "…" : ""
        let suffix = end != text.endIndex ? "…" : ""
        let prefixLength = (prefix as NSString).length
        let visibleRange = sourceRange.location..<(sourceRange.location + sourceRange.length)
        let visibleMatches = ranges.compactMap { range -> NSRange? in
            let matchRange = range.location..<(range.location + range.length)
            let overlap = matchRange.clamped(to: visibleRange)
            guard !overlap.isEmpty else { return nil }
            return NSRange(
                location: overlap.lowerBound - sourceRange.location + prefixLength,
                length: overlap.count
            )
        }
        return Presentation(
            text: prefix + String(text[start..<end]) + suffix,
            ranges: visibleMatches
        )
    }
}
