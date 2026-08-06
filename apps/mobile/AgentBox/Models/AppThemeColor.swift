import SwiftUI

enum AppThemeColor: String, CaseIterable, Identifiable, Sendable {
    case blue
    case indigo
    case purple
    case pink
    case red
    case orange
    case brown
    case green
    case teal
    case cyan
    case graphite
    case monochrome

    static let defaultColor: AppThemeColor = .monochrome

    var id: String { rawValue }

    var name: String {
        switch self {
        case .blue: "Blue"
        case .indigo: "Indigo"
        case .purple: "Purple"
        case .pink: "Pink"
        case .red: "Red"
        case .orange: "Orange"
        case .brown: "Brown"
        case .green: "Green"
        case .teal: "Teal"
        case .cyan: "Cyan"
        case .graphite: "Graphite"
        case .monochrome: "Black / white"
        }
    }

    var color: Color {
        switch self {
        case .blue: Color(uiColor: .systemBlue)
        case .indigo: Color(uiColor: .systemIndigo)
        case .purple: Color(uiColor: .systemPurple)
        case .pink: Color(uiColor: .systemPink)
        case .red: Color(uiColor: .systemRed)
        case .orange: Color(uiColor: .systemOrange)
        case .brown: Color(uiColor: .systemBrown)
        case .green: Color(uiColor: .systemGreen)
        case .teal: Color(uiColor: .systemTeal)
        case .cyan: Color(uiColor: .systemCyan)
        case .graphite: Color(uiColor: .systemGray)
        case .monochrome: .primary
        }
    }

    var foregroundColor: Color {
        switch self {
        case .monochrome: Color(uiColor: .systemBackground)
        default: .white
        }
    }

    var appBackgroundColor: Color {
        Color(
            uiColor: UIColor { traits in
                guard traits.userInterfaceStyle != .dark else { return .black }
                return UIColor.white.mixed(
                    with: uiColor,
                    amount: 0.025,
                    traits: traits
                )
            }
        )
    }

    static var cardBackgroundColor: Color {
        Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(white: 0.05, alpha: 1)
                    : .white
            }
        )
    }

    private var uiColor: UIColor {
        switch self {
        case .blue: .systemBlue
        case .indigo: .systemIndigo
        case .purple: .systemPurple
        case .pink: .systemPink
        case .red: .systemRed
        case .orange: .systemOrange
        case .brown: .systemBrown
        case .green: .systemGreen
        case .teal: .systemTeal
        case .cyan: .systemCyan
        case .graphite: .systemGray
        case .monochrome: .label
        }
    }
}

private extension UIColor {
    func mixed(
        with color: UIColor,
        amount: CGFloat,
        traits: UITraitCollection
    ) -> UIColor {
        let start = resolvedColor(with: traits)
        let end = color.resolvedColor(with: traits)
        var startRed: CGFloat = 0
        var startGreen: CGFloat = 0
        var startBlue: CGFloat = 0
        var startAlpha: CGFloat = 0
        var endRed: CGFloat = 0
        var endGreen: CGFloat = 0
        var endBlue: CGFloat = 0
        var endAlpha: CGFloat = 0

        guard start.getRed(
            &startRed,
            green: &startGreen,
            blue: &startBlue,
            alpha: &startAlpha
        ),
            end.getRed(
                &endRed,
                green: &endGreen,
                blue: &endBlue,
                alpha: &endAlpha
            )
        else { return start }

        return UIColor(
            red: startRed + (endRed - startRed) * amount,
            green: startGreen + (endGreen - startGreen) * amount,
            blue: startBlue + (endBlue - startBlue) * amount,
            alpha: startAlpha + (endAlpha - startAlpha) * amount
        )
    }
}
