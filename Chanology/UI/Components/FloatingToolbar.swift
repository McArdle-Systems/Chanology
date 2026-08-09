import SwiftUI

// MARK: - ToolbarAction

struct ToolbarAction: Identifiable {
    enum Role {
        case standard
        case prominent
        case destructive
        case muted
    }

    let id: String
    let icon: String
    let label: String
    var role: Role = .standard
    var isEnabled: Bool = true
    var showSlash: Bool = false
    var badge: String? = nil
    let action: () -> Void

    init(
        id: String? = nil,
        icon: String,
        label: String,
        role: Role = .standard,
        isEnabled: Bool = true,
        showSlash: Bool = false,
        badge: String? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id ?? "\(icon)-\(label)"
        self.icon = icon
        self.label = label
        self.role = role
        self.isEnabled = isEnabled
        self.showSlash = showSlash
        self.badge = badge
        self.action = action
    }
}

// MARK: - Side

enum FloatingToolbarSide: String, Hashable, CaseIterable {
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
        VStack(spacing: 12) {
            ForEach(actions) { action in
                ToolbarButton(action: action, isToolbarArmed: isArmed)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .simultaneousGesture(flipGesture)
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
    let isToolbarArmed: Bool

    var body: some View {
        Button(action: action.action) {
            Image(systemName: action.icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(foreground)
                .background(discBackground)
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(isToolbarArmed ? 0.18 : 0.10),
                        radius: isToolbarArmed ? 8 : 4,
                        x: 0, y: isToolbarArmed ? 3 : 1)
                .contentShape(Circle())
                .overlay(alignment: .topTrailing) { badgeView }
                .overlay { slashOverlay }
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
        .opacity(!action.isEnabled && action.role != .muted ? 0.4 : 1)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var discBackground: some View {
        switch action.role {
        case .prominent:
            Circle().fill(Color.accentColor)
        default:
            Circle().fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var slashOverlay: some View {
        if action.showSlash {
            Rectangle()
                .frame(width: 2, height: 50)
                .rotationEffect(.degrees(45))
                .foregroundStyle(.primary.opacity(0.45))
                .clipShape(Circle())
        }
    }

    @ViewBuilder
    private var badgeView: some View {
        if let badge = action.badge, !badge.isEmpty {
            Text(badge)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 16, minHeight: 16)
                .background(Color.accentColor, in: Capsule(style: .continuous))
                .overlay(Capsule().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
                .offset(x: 4, y: -4)
        }
    }

    private var accessibilityLabel: String {
        if let badge = action.badge, !badge.isEmpty {
            return "\(action.label), \(badge)"
        }
        return action.label
    }

    private var foreground: Color {
        switch action.role {
        case .standard:    return .primary
        case .prominent:   return .white
        case .destructive: return .red
        case .muted:       return .secondary
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
            ToolbarAction(icon: "magnifyingglass", label: "Search thread", action: {}),
            ToolbarAction(icon: "bell.fill", label: "Stop watching", role: .prominent, action: {}),
            ToolbarAction(icon: "square.and.pencil", label: "Reply", role: .prominent, action: {}),
            ToolbarAction(icon: "arrow.down", label: "Scroll to bottom", action: {}),
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
