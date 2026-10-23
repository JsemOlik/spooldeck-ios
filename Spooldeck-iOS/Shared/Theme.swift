import SwiftUI
import UIKit

/// Colours and shapes from the web app's theme (src/app/globals.css), converted from OKLCH.
enum Theme {
    static let background = dynamic(light: 0xFFFFFF, dark: 0x0A0A0A)
    /// Behind grouped forms, where rows sit on the system's cell colour.
    static let groupedBackground = dynamic(light: 0xF5F5F5, dark: 0x0A0A0A)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x171717)
    static let muted = dynamic(light: 0xF5F5F5, dark: 0x262626)
    static let mutedForeground = dynamic(light: 0x737373, dark: 0xA1A1A1)
    static let border = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.10) : UIColor(hex: 0xE5E5E5)
    })
    static let input = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.15) : UIColor(hex: 0xE5E5E5)
    })
    static let primary = dynamic(light: 0xDF5200, dark: 0xF77E35)
    static let primaryForeground = dynamic(light: 0xFCFCFC, dark: 0x190F0B)
    static let destructive = dynamic(light: 0xE7000B, dark: 0xFF6467)

    static let radius: CGFloat = 14
    static let controlRadius: CGFloat = 10
    static let spacing: CGFloat = 16

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Screens and cards

extension View {
    /// A scrolling screen of cards on the app background, like the web pages.
    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }

    /// Grouped forms and settings: system rows on the themed background.
    func themedForm() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.groupedBackground.ignoresSafeArea())
    }

    /// The bordered card surface used across the web app.
    func cardStyle(padding: CGFloat = Theme.spacing) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.border))
    }
}

/// A scroll view laid out like a web page: a column of cards with even spacing.
struct Screen<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                content
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .screenBackground()
    }
}

/// A titled card ("Usage history", "Print settings"…).
struct Card<Content: View, Accessory: View, Trailing: View>: View {
    let title: String?
    var systemImage: String?
    var iconColor: Color
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    init(
        _ title: String? = nil,
        systemImage: String? = nil,
        iconColor: Color = Theme.mutedForeground,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.iconColor = iconColor
        self.accessory = accessory()
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 8) {
                    if let systemImage {
                        Image(systemName: systemImage).font(.subheadline.weight(.semibold)).foregroundStyle(iconColor)
                    }
                    Text(title).font(.headline)
                    accessory
                    Spacer(minLength: 0)
                    trailing
                }
            }
            content
        }
        .cardStyle()
    }
}

/// Hairline between rows inside a card.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Theme.border).frame(height: 1)
    }
}

/// Rows separated by hairlines, like the web's `divide-y` lists.
struct DividedRows<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let data: Data
    @ViewBuilder let row: (Data.Element) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                if index > 0 { RowDivider() }
                row(element)
            }
        }
    }
}

// MARK: - Buttons

enum SpoolButtonKind {
    case primary, outline, ghost, destructive
}

/// Buttons styled after the web's shadcn buttons, with native press feedback.
struct SpoolButtonStyle: ButtonStyle {
    var kind: SpoolButtonKind = .primary
    var fullWidth = false
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.medium) : .body.weight(.medium))
            .labelStyle(SpoolButtonLabelStyle())
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, compact ? 12 : (fullWidth ? 10 : 16))
            .frame(minHeight: compact ? 34 : 44)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay {
                if kind == .outline {
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.input)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Theme.primaryForeground
        case .outline, .ghost: .primary
        case .destructive: .white
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Theme.primary
        case .outline: Theme.card
        case .ghost: .clear
        case .destructive: Theme.destructive
        }
    }
}

private struct SpoolButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.imageScale(.medium)
            configuration.title
        }
    }
}

extension ButtonStyle where Self == SpoolButtonStyle {
    static var spoolPrimary: SpoolButtonStyle { SpoolButtonStyle(kind: .primary) }
    static var spoolOutline: SpoolButtonStyle { SpoolButtonStyle(kind: .outline) }
    static func spool(_ kind: SpoolButtonKind, fullWidth: Bool = false, compact: Bool = false) -> SpoolButtonStyle {
        SpoolButtonStyle(kind: kind, fullWidth: fullWidth, compact: compact)
    }
}

/// A square icon button with an outline, like the web's "…" menu trigger.
struct IconButtonLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.medium))
            .frame(width: 44, height: 44)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.input))
            .contentShape(Rectangle())
    }
}

/// A text link in the primary colour, like the web's "All notes →".
struct ArrowLink: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text("\(title) →").font(.subheadline.weight(.medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.primary)
    }
}

// MARK: - Logo

/// The Spooldeck mark: an orange disc with a dashed ring and a hub.
struct LogoMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(Theme.primary)
            Circle()
                .stroke(Theme.primaryForeground, style: StrokeStyle(lineWidth: size * 2 / 32, dash: [size * 3 / 32, size * 2.2 / 32]))
                .frame(width: size * 18 / 32, height: size * 18 / 32)
            Circle().fill(Theme.primaryForeground).frame(width: size / 4, height: size / 4)
        }
        .frame(width: size * 28 / 32, height: size * 28 / 32)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
