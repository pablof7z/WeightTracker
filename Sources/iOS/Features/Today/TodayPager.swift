import SwiftUI

struct TodayPager: View {
    @AppStorage("today.swipeUpHintDismissed") private var hintDismissed: Bool = false
    @State private var pageID: TodayPage? = .weight

    enum TodayPage: Int, Hashable { case weight, meals }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                TodayView()
                    .containerRelativeFrame(.vertical)
                    .id(TodayPage.weight)

                MealAgendaPage()
                    .containerRelativeFrame(.vertical)
                    .id(TodayPage.meals)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $pageID)
        .scrollIndicators(.hidden)
        // Drive hint dismissal from the actual page change, not from a layout-time
        // onAppear (which fires immediately because containerRelativeFrame
        // materializes both pages on first layout).
        .onChange(of: pageID) { _, newValue in
            if newValue == .meals, !hintDismissed {
                withAnimation(.easeInOut(duration: 0.25)) {
                    hintDismissed = true
                }
            }
        }
        .overlay(alignment: .bottom) {
            // Only show the hint while the user is on the weight page and they
            // haven't seen the meals page yet. Animate the appearance/dismissal.
            if !hintDismissed && pageID == .weight {
                SwipeUpHint()
                    .padding(.bottom, 96)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: hintDismissed)
        .animation(.easeInOut(duration: 0.2), value: pageID)
    }
}
