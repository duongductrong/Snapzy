import SwiftUI

struct AnnotateCombineControlsView: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    // Images are placed where they are dropped and then move freely, so the sidebar only
    // keeps the gap: the spacing a dropped image lands at and dragged images snap to.
    VStack(alignment: .leading, spacing: Spacing.sm) {
      SidebarSectionHeader(title: L10n.Combine.spacing)
      CompactSliderRow(
        label: L10n.Combine.imageGap,
        value: Binding(
          get: { state.combineGap },
          set: { state.setCombineGap($0) }
        ),
        range: 0 ... 80
      )
    }
  }
}
