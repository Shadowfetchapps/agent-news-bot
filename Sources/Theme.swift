import SwiftUI

enum Theme {
    static let bgDeep = Color(red: 0.045, green: 0.055, blue: 0.08)
    static let bgRaised = Color(red: 0.08, green: 0.10, blue: 0.14)
    static let bgCard = Color(red: 0.11, green: 0.13, blue: 0.18)
    static let stroke = Color.white.opacity(0.08)
    static let textHi = Color(red: 0.93, green: 0.95, blue: 0.97)
    static let textMed = Color(red: 0.70, green: 0.75, blue: 0.82)
    static let textLow = Color(red: 0.50, green: 0.55, blue: 0.62)
    static let gold = Color(red: 0.84, green: 0.66, blue: 0.33)
    static let aqua = Color(red: 0.35, green: 0.78, blue: 0.84)
    static let success = Color(red: 0.40, green: 0.82, blue: 0.58)
    static let warning = Color(red: 0.95, green: 0.72, blue: 0.28)
    static let danger = Color(red: 0.90, green: 0.38, blue: 0.38)
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func anbCard() -> some View { modifier(CardStyle()) }
}
