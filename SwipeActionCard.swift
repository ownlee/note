import SwiftUI

struct CardSwipeAction {
    let title: String
    let systemImage: String
    let tint: Color
    let handler: () -> Void

    init(
        title: String,
        systemImage: String,
        tint: Color,
        handler: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.handler = handler
    }
}

struct SwipeActionCard<Content: View>: View {
    private let commitDistance: CGFloat = 96

    let leadingAction: CardSwipeAction
    let trailingAction: CardSwipeAction
    let content: Content

    @State private var horizontalOffset: CGFloat = 0

    init(
        leadingAction: CardSwipeAction,
        trailingAction: CardSwipeAction,
        @ViewBuilder content: () -> Content
    ) {
        self.leadingAction = leadingAction
        self.trailingAction = trailingAction
        self.content = content()
    }

    var body: some View {
        ZStack {
            swipeActionHint

            content
                .frame(maxWidth: .infinity)
                .offset(x: horizontalOffset)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .highPriorityGesture(swipeGesture)
        .accessibilityAction(named: Text(leadingAction.title)) {
            leadingAction.handler()
        }
        .accessibilityAction(named: Text(trailingAction.title)) {
            trailingAction.handler()
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged(updateOffset)
            .onEnded(commitSwipe)
    }

    @ViewBuilder
    private var swipeActionHint: some View {
        if horizontalOffset > 0 {
            HStack {
                actionLabel(leadingAction)
                    .padding(.leading, 18)
                Spacer(minLength: 0)
            }
        } else if horizontalOffset < 0 {
            HStack {
                Spacer(minLength: 0)
                actionLabel(trailingAction)
                    .padding(.trailing, 18)
            }
        }
    }

    private func actionLabel(_ action: CardSwipeAction) -> some View {
        Label(action.title, systemImage: action.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(action.tint)
            .opacity(min(abs(horizontalOffset) / commitDistance, 1))
    }

    private func updateOffset(_ value: DragGesture.Value) {
        guard abs(value.translation.width) > abs(value.translation.height) else { return }
        horizontalOffset = min(
            commitDistance,
            max(-commitDistance, value.translation.width)
        )
    }

    private func commitSwipe(_ value: DragGesture.Value) {
        guard abs(value.translation.width) > abs(value.translation.height) else {
            resetOffset()
            return
        }

        let shouldCommitLeading = value.translation.width >= commitDistance
            || value.predictedEndTranslation.width >= commitDistance * 1.35
        let shouldCommitTrailing = value.translation.width <= -commitDistance
            || value.predictedEndTranslation.width <= -(commitDistance * 1.35)

        resetOffset()
        if shouldCommitLeading {
            performAfterGesture(leadingAction)
        } else if shouldCommitTrailing {
            performAfterGesture(trailingAction)
        }
    }

    private func resetOffset() {
        withAnimation(.snappy) {
            horizontalOffset = 0
        }
    }

    private func performAfterGesture(_ action: CardSwipeAction) {
        Task { @MainActor in
            // Finish the drag transaction before presenting a sheet or
            // mutating the SwiftData collection around this card.
            await Task.yield()
            action.handler()
        }
    }
}
