import SwiftUI

// MARK: - Palette

enum ScarlettUI {
    static let accent = Color.orange
    static let off = Color.gray.opacity(0.4)
    static let border = Color.primary.opacity(0.14)
    static let secondaryText = Color.white.opacity(0.78)

    static let stripFill = Color.white.opacity(0.90)
    static let panelFill = Color(nsColor: .controlBackgroundColor)
    static let panelBackground = Color.black.opacity(0.22)

    static let background = LinearGradient(
        colors: [
            Color(red: 0.42, green: 0.025, blue: 0.035),
            Color(red: 0.22, green: 0.012, blue: 0.020),
            Color(red: 0.07, green: 0.005, blue: 0.010)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let meterTrack = Color.black.opacity(0.25)
    static let faderTrack = Color.gray.opacity(0.2)
    static let faderFill = Color.primary.opacity(0.12)
    static let faderKnob = Color.white.opacity(0.85)
    static let knobShadow = Color.black.opacity(0.25)

    // MARK: - Fonts

    static func title(_ size: CGFloat = 12, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat = 11, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Meters

    static func meterColor(_ level: CGFloat, _ base: Color) -> Color {
        level > 0.8 ? .red : level > 0.6 ? .yellow : base
    }
}

// MARK: - Section Title

extension View {
    /// Light, high-contrast chip for native controls (pickers) sitting on the
    /// dark panel background. Deterministic in light and dark mode.
    func chipStyle() -> some View {
        padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0.95, green: 0.95, blue: 0.97))
            )
            .foregroundStyle(.black)
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(ScarlettUI.title(11))
            .foregroundStyle(ScarlettUI.secondaryText)
    }
}

// MARK: - Toggle Button

struct ToggleButton: View {
    let label: String
    var isOn: Bool = false
    var onColor: Color = .orange
    var offColor: Color = ScarlettUI.off
    var font: Font = .system(size: 8, weight: .bold)
    var controlSize: ControlSize = .small
    var minWidth: CGFloat? = nil
    var height: CGFloat = 18
    let action: () -> Void

    var body: some View {
        Button(label, action: action)
            .font(font)
            .buttonStyle(.bordered)
            .tint(isOn ? onColor : offColor)
            .controlSize(controlSize)
            .frame(maxWidth: minWidth.map { _ in .infinity }, minHeight: height)
            .frame(height: height)
    }
}

// MARK: - Meter Bar

struct MeterBar: View {
    var level: CGFloat
    var color: Color
    var hold: CGFloat? = nil
    var onResetHold: (() -> Void)? = nil
    var width: CGFloat = 7
    var height: CGFloat = 160

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 1)
                .fill(ScarlettUI.meterTrack)
            RoundedRectangle(cornerRadius: 1)
                .fill(ScarlettUI.meterColor(level, color))
                .frame(height: max(1, height * min(level, 1)))
                .animation(.linear(duration: 0.05), value: level)
            if let hold {
                let clamped = min(1, max(0, hold))
                Rectangle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: width + 2, height: 1.5)
                    .frame(width: width, height: height)
                    .offset(y: height / 2 - 0.75 - clamped * height)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
        .onTapGesture(count: 2) { onResetHold?() }
        .help("Double-click: reset peak hold")
    }
}

// MARK: - Fader

struct Fader: View {
    var position: CGFloat
    var onChange: (CGFloat) -> Void
    var onDoubleTap: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(ScarlettUI.faderTrack)
                    .frame(width: 28)
                RoundedRectangle(cornerRadius: 1)
                    .fill(ScarlettUI.faderFill)
                    .frame(width: 28, height: position * (geo.size.height - 4))
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .overlay(alignment: .bottom) {
                Circle()
                    .fill(ScarlettUI.faderKnob)
                    .frame(width: 22, height: 22)
                    .shadow(color: ScarlettUI.knobShadow, radius: 1)
                    .offset(y: -(position * geo.size.height))
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    onChange(min(1, max(0, 1 - (v.location.y / geo.size.height))))
                }
            )
            .onTapGesture(count: 2) { onDoubleTap?() }
        }
    }
}
