import SwiftUI

/// FlareStore-style segmented control: ONE highlight capsule slides between equal-width segments
/// (matchedGeometryEffect follower), labels cross-fade between selected / secondary colours, a
/// light haptic on tap, drag across to scrub, clipped to its capsule, 44 pt+ tall, read by
/// VoiceOver as an adjustable picker. Reduce Motion: the highlight cross-fades instead of sliding.
///
/// The highlight follows a local copy of the selection, so it animates even when the binding is
/// backed by @AppStorage (whose writes don't carry the animation transaction).
struct SlidingSegmentedControl<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        var systemImage: String? = nil
        var id: Value { value }
    }

    @Binding var selection: Value
    let options: [Option]
    /// VoiceOver name of the control ("Appearance", "Sort by"…).
    var accessibilityTitle: String = "Options"

    @Environment(\.themeAccent) private var accent
    @Environment(\.themeGradient) private var gradient
    @Environment(\.themeOnAccent) private var onAccent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Namespace private var namespace

    @State private var shown: Value?
    @State private var width: CGFloat = 0
    @State private var scrubbing = false

    private var current: Value { shown ?? selection }
    private var animation: Animation { reduceMotion ? Motion.fade : Motion.selection }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .background(alignment: .leading) {
            if !reduceMotion, options.contains(where: { $0.value == current }) {
                highlight
                    .matchedGeometryEffect(id: current, in: namespace, properties: .frame, isSource: false)
            }
        }
        .padding(Space.x1)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .overlay(Capsule().strokeBorder(SemanticColor.hairline, lineWidth: Border.width))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { width = geo.size.width }
                .onChange(of: geo.size.width) { width = $0 }
        })
        .gesture(dragGesture)
        .opacity(isEnabled ? 1 : 0.5)
        .onChange(of: selection) { newValue in
            guard shown != newValue else { return }
            withAnimation(animation) { shown = newValue }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(options.first { $0.value == current }?.title ?? "")
        .accessibilityHint("Swipe up or down to change")
        .accessibilityAdjustableAction { direction in
            guard let index = options.firstIndex(where: { $0.value == current }) else { return }
            switch direction {
            case .increment: commit(min(index + 1, options.count - 1))
            case .decrement: commit(max(index - 1, 0))
            @unknown default: break
            }
        }
    }

    private var highlight: some View {
        Capsule()
            .fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: Border.width))
            .shadow(color: accent.opacity(0.3), radius: 6, y: 2)
    }

    private func segment(_ option: Option) -> some View {
        let selected = option.value == current
        return HStack(spacing: Space.x1 + 2) {
            if let image = option.systemImage {
                Image(systemName: image)
                    .symbolBounce(value: selected)
            }
            Text(option.title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(TypeScale.subheadline.weight(.semibold))
        .foregroundColor(selected ? onAccent : SemanticColor.textSecondary)
        .padding(.horizontal, Space.x2)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background {
            if reduceMotion {
                highlight.opacity(selected ? 1 : 0)
            }
        }
        .background(
            Color.clear.matchedGeometryEffect(id: option.value, in: namespace, properties: .frame, isSource: true)
        )
        .contentShape(Rectangle())
    }

    // MARK: Interaction

    private func index(at x: CGFloat) -> Int {
        guard !options.isEmpty, width > 0 else { return 0 }
        let segmentWidth = width / CGFloat(options.count)
        return min(max(Int(x / segmentWidth), 0), options.count - 1)
    }

    /// Tap selects on touch-up; a horizontal drag scrubs across the segments.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !scrubbing && abs(value.translation.width) > 8 && abs(value.translation.width) > abs(value.translation.height) {
                    scrubbing = true
                }
                guard scrubbing else { return }
                let target = options[index(at: value.location.x)].value
                guard target != current else { return }
                Haptics.selection()
                withAnimation(animation) { shown = target }
            }
            .onEnded { value in
                defer { scrubbing = false }
                // A drag that left the control vertically (a scroll attempt) changes nothing.
                if !scrubbing && abs(value.translation.height) > 24 { return }
                commit(index(at: value.location.x))
            }
    }

    private func commit(_ index: Int) {
        let target = options[index].value
        let changed = target != selection
        if target != current || changed { Haptics.impact(.light) }
        withAnimation(animation) {
            shown = target
            if changed { selection = target }
        }
    }
}
