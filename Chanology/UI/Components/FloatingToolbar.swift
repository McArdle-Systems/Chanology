import SwiftUI

// MARK: - ToolbarAction

struct ToolbarAction: Identifiable {
    enum Role {
        case standard
        case prominent
        case destructive
    }

    let id: String
    let icon: String
    let label: String
    var role: Role = .standard
    var isEnabled: Bool = true
    let action: () -> Void

    init(
        id: String? = nil,
        icon: String,
        label: String,
        role: Role = .standard,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.id = id ?? "\(icon)-\(label)"
        self.icon = icon
        self.label = label
        self.role = role
        self.isEnabled = isEnabled
        self.action = action
    }
}

// MARK: - Side

enum FloatingToolbarSide: Hashable {
    case leading, trailing

    var flipped: FloatingToolbarSide { self == .leading ? .trailing : .leading }
}

// MARK: - FloatingToolbar

struct FloatingToolbar: View {
    let actions: [ToolbarAction]
    @Binding var side: FloatingToolbarSide

    /// Horizontal drag distance (in points) past which a flick flips sides.
    var flipThreshold: CGFloat = 60

    /// Long-press duration that arms the side-flip drag.
    var longPressDuration: Double = 0.35

    @State private var isArmed = false
    @State private var dragOffset: CGFloat = 0
    @GestureState private var isLongPressing = false

    var body: some View {
        HStack(spacing: 0) {
            if side == .trailing { Spacer(minLength: 0) }
            toolbarStack
                .offset(x: dragOffset)
                .scaleEffect(isArmed ? 1.04 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: side)
                .animation(.easeOut(duration: 0.15), value: isArmed)
            if side == .leading { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 12)
        .allowsHitTesting(true)
    }

    private var toolbarStack: some View {
        VStack(spacing: 4) {
            ForEach(actions) { action in
                ToolbarButton(action: action)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(isArmed ? 0.20 : 0.10),
                radius: isArmed ? 14 : 8,
                x: 0, y: isArmed ? 6 : 3)
        .gesture(flipGesture)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Floating toolbar")
        .accessibilityHint("Long-press and flick horizontally to switch sides")
    }

    private var flipGesture: some Gesture {
        LongPressGesture(minimumDuration: longPressDuration)
            .updating($isLongPressing) { current, state, _ in state = current }
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .second(true, let drag?):
                    if !isArmed {
                        isArmed = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    dragOffset = clampedDrag(drag.translation.width)
                default:
                    break
                }
            }
            .onEnded { value in
                defer {
                    isArmed = false
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        dragOffset = 0
                    }
                }
                guard case .second(true, let drag?) = value else { return }
                let dx = drag.translation.width
                let wantsFlip = (side == .leading && dx > flipThreshold)
                              || (side == .trailing && dx < -flipThreshold)
                if wantsFlip {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    side = side.flipped
                }
            }
    }

    private func clampedDrag(_ dx: CGFloat) -> CGFloat {
        let max: CGFloat = 80
        return min(max, Swift.max(-max, dx))
    }
}

// MARK: - ToolbarButton

private struct ToolbarButton: View {
    let action: ToolbarAction

    var body: some View {
        Button(action: action.action) {
            Image(systemName: action.icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(foreground)
                .background(background, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
        .opacity(action.isEnabled ? 1 : 0.4)
        .accessibilityLabel(action.label)
    }

    private var foreground: Color {
        switch action.role {
        case .standard:    return .primary
        case .prominent:   return .white
        case .destructive: return .red
        }
    }

    private var background: Color {
        switch action.role {
        case .prominent: return .accentColor
        default:         return .clear
        }
    }
}

// MARK: - Previews

#Preview("ThreadView actions — leading") {
    FloatingToolbarPreviewHost(initialSide: .leading, actions: .threadSample)
}

#Preview("ThreadView actions — trailing") {
    FloatingToolbarPreviewHost(initialSide: .trailing, actions: .threadSample)
}

#Preview("BoardView actions") {
    FloatingToolbarPreviewHost(initialSide: .trailing, actions: .boardSample)
}

#Preview("Dark mode") {
    FloatingToolbarPreviewHost(initialSide: .trailing, actions: .threadSample)
        .preferredColorScheme(.dark)
}

private struct FloatingToolbarPreviewHost: View {
    @State var side: FloatingToolbarSide
    let actions: [ToolbarAction]

    init(initialSide: FloatingToolbarSide, actions: [ToolbarAction]) {
        _side = State(initialValue: initialSide)
        self.actions = actions
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.25), .purple.opacity(0.25), .orange.opacity(0.2)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack {
                Text("Long-press the toolbar, then flick →/← to swap sides.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            }

            FloatingToolbar(actions: actions, side: $side)
        }
    }
}

private extension Array where Element == ToolbarAction {
    static var threadSample: [ToolbarAction] {
        [
            ToolbarAction(icon: "arrow.up", label: "Scroll to top", action: {}),
            ToolbarAction(icon: "arrow.down", label: "Scroll to bottom", action: {}),
            ToolbarAction(icon: "magnifyingglass", label: "Search thread", action: {}),
            ToolbarAction(icon: "square.and.pencil", label: "Reply", role: .prominent, action: {}),
            ToolbarAction(icon: "bell.slash", label: "Mute", action: {}),
        ]
    }

    static var boardSample: [ToolbarAction] {
        [
            ToolbarAction(icon: "arrow.up.circle", label: "Refresh", action: {}),
            ToolbarAction(icon: "magnifyingglass", label: "Search board", action: {}),
            ToolbarAction(icon: "line.3.horizontal.decrease.circle", label: "Filter", action: {}),
            ToolbarAction(icon: "square.and.pencil", label: "New thread", role: .prominent, action: {}),
        ]
    }
}
