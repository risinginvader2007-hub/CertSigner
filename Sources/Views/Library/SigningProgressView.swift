import SwiftUI

/// Reusable signing progress UI: ring, step list, live log, result state.
/// Stage 4 drives it from the real zsign pipeline.
struct SigningProgressView: View {
    var currentStep: SigningStep?
    var progress: Double
    var log: [LogLine]
    var result: AnimatedResultIcon.Result?
    var failureMessage: String?

    @Environment(\.themeAccent) private var accent
    @State private var shakes = 0

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                if let result {
                    AnimatedResultIcon(result: result, size: 132)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    ProgressRing(progress: progress, lineWidth: 12)
                        .frame(width: 132, height: 132)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 140)
            .shake(shakes)
            .animation(Theme.bouncy, value: result)

            if let failureMessage, result == .failure {
                Text(failureMessage)
                    .font(.subheadline)
                    .foregroundColor(Theme.danger)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            stepList
            logView
        }
        .onChange(of: result) { newValue in
            if newValue == .failure {
                withAnimation(.linear(duration: 0.45)) { shakes += 1 }
            }
        }
    }

    private var stepList: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(SigningStep.allCases) { step in
                    HStack(spacing: 12) {
                        stepIcon(step)
                            .frame(width: 26, height: 26)
                        Text(step.title)
                            .font(.subheadline.weight(state(step) == .active ? .semibold : .regular))
                            .foregroundColor(state(step) == .pending ? .secondary : .primary)
                        Spacer()
                        if state(step) == .active {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .animation(Theme.spring, value: currentStep)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(stateLabel(step))
                }
            }
        }
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LOG")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(log) { line in
                            Text(line.text)
                                .font(.system(.caption, design: .rounded))
                                .foregroundColor(line.isError ? Theme.danger : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(12)
                }
                .frame(height: 150)
                .cardBackground(cornerRadius: Theme.smallCorner)
                .onChange(of: log.count) { _ in
                    if let last = log.last {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private enum StepState { case pending, active, done, failed }

    private func state(_ step: SigningStep) -> StepState {
        if result == .success { return .done }
        guard let currentStep else { return .pending }
        if step.rawValue < currentStep.rawValue { return .done }
        if step == currentStep { return result == .failure ? .failed : .active }
        return .pending
    }

    private func stateLabel(_ step: SigningStep) -> String {
        switch state(step) {
        case .pending: return "Pending"
        case .active: return "In progress"
        case .done: return "Done"
        case .failed: return "Failed"
        }
    }

    @ViewBuilder
    private func stepIcon(_ step: SigningStep) -> some View {
        switch state(step) {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundColor(Theme.success)
                .transition(.scale.combined(with: .opacity))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundColor(Theme.danger)
        case .active:
            Image(systemName: step.systemImage)
                .font(.body.weight(.semibold))
                .foregroundColor(accent)
        case .pending:
            Image(systemName: step.systemImage)
                .font(.body)
                .foregroundColor(.secondary.opacity(0.6))
        }
    }
}
