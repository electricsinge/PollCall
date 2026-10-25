import SwiftUI

// MARK: - Poll Call brand
//
// Name: Poll Call — like a roll call, it keeps calling your name until you vote.
// Mark: a marigold circle with a check that breaks out of it. Done, and then some.
// Deliberately nonpartisan: no red-vs-blue. Deep civic teal + marigold.

enum Brand {
    static let name = "Poll Call"

    /// Deep civic teal: headlines, toggles, links, Election Day pins.
    static let ink = Color(light: 0x0B3B3C, dark: 0x5CC6B4)
    /// Marigold: the action color. The mark, the I voted button, early voting pins.
    static let marigold = Color(hex: 0xF5B301)
    /// Text and icons that sit on marigold (never white; it fails contrast).
    static let onMarigold = Color(hex: 0x0B3B3C)
    /// Quiet neutral for secondary things like drop boxes.
    static let slate = Color(light: 0x5B6B73, dark: 0x9AA8AF)
    static let paper = Color(hex: 0xFFFFFF)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

// MARK: - Mark

/// The Poll Call mark. Same geometry as the app icon (drawn in its 1024-pt space).
struct PollCallMark: View {
    /// Height in points; width follows the mark's proportions.
    var height: CGFloat = 28

    // Bounding box of the mark inside the 1024 icon canvas.
    private static let box = CGRect(x: 170, y: 250, width: 670, height: 610)

    var body: some View {
        Canvas { ctx, size in
            let s = size.height / Self.box.height
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: (x - Self.box.minX) * s, y: (y - Self.box.minY) * s)
            }
            let center = p(468, 564)
            let r = 286 * s
            let disc = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))

            var tick = Path()
            tick.move(to: p(322, 566))
            tick.addLine(to: p(432, 676))
            tick.addLine(to: p(778, 316))
            let style = StrokeStyle(lineWidth: 92 * s, lineCap: .round, lineJoin: .round)

            ctx.fill(disc, with: .color(Brand.marigold))
            ctx.stroke(tick, with: .color(Brand.marigold), style: style)   // part outside the disc
            ctx.clip(to: disc)
            ctx.stroke(tick, with: .color(Brand.onMarigold), style: style) // part inside the disc
        }
        .frame(width: height * Self.box.width / Self.box.height, height: height)
        .accessibilityHidden(true)
    }
}

struct Wordmark: View {
    var body: some View {
        HStack(spacing: 8) {
            PollCallMark(height: 22)
            Text(Brand.name)
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(Brand.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Brand.name)
    }
}

// MARK: - I voted

/// The one marigold button in the app.
struct IVotedButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("I voted", systemImage: "checkmark")
                .font(.system(.title2, design: .rounded).weight(.black))
                .foregroundStyle(Brand.onMarigold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Brand.marigold, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// A clean round "I voted" sticker with the date.
struct IVotedSticker: View {
    var date: Date = .now
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            Circle().fill(Brand.marigold)
            Circle().fill(Brand.paper).padding(size * 0.07)
            VStack(spacing: size * 0.01) {
                Text("I voted")
                    .font(.system(size: size * 0.2, weight: .black, design: .rounded))
                Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.system(size: size * 0.085, weight: .semibold, design: .rounded))
                    .opacity(0.65)
            }
            .foregroundStyle(Brand.onMarigold)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("I voted sticker")
    }
}

/// Shown after "I voted": the sticker lands, reminders stop.
struct VotedBadge: View {
    var stickerSize: CGFloat = 104
    let onUndo: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    private var votedAt: Date {
        (UserDefaults.standard.object(forKey: ReminderScheduler.votedAtKey) as? Date) ?? .now
    }

    var body: some View {
        HStack(spacing: 16) {
            IVotedSticker(date: votedAt, size: stickerSize)
                .scaleEffect(landed ? 1 : 1.5)
                .opacity(landed ? 1 : 0)
            VStack(alignment: .leading, spacing: 4) {
                Text("You voted.")
                    .font(.system(.title2, design: .rounded).weight(.black))
                    .foregroundStyle(Brand.ink)
                Text("We'll stop calling.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Undo", action: onUndo)
                    .font(.footnote.weight(.semibold))
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .onAppear {
            if reduceMotion {
                landed = true
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { landed = true }
            }
        }
    }
}

#Preview("Brand") {
    VStack(spacing: 32) {
        PollCallMark(height: 120)
        Wordmark()
        IVotedSticker()
        IVotedButton {}
    }
    .padding()
}
