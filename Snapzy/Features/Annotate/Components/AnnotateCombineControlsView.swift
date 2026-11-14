import SwiftUI

struct AnnotateCombineModePicker: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    Picker(
      L10n.Combine.mode,
      selection: Binding(
        get: { state.combineMode },
        set: { state.setCombineMode($0) }
      )
    ) {
      Text(L10n.Combine.autoStitch).tag(CombineImagesMode.autoStitch)
      Text(L10n.Combine.freeCanvas).tag(CombineImagesMode.freeCanvas)
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .frame(maxWidth: .infinity)
  }
}

struct AnnotateCombineControlsView: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    // Arrangement and order follow where images are dropped or dragged on the canvas,
    // so the sidebar only keeps the mode and the gap.
    VStack(alignment: .leading, spacing: Spacing.md) {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        SidebarSectionHeader(title: L10n.Combine.mode)
        AnnotateCombineModePicker(state: state)
      }

      Divider().background(Color(nsColor: .separatorColor))

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
      .disabled(state.combineMode == .freeCanvas)
      .opacity(state.combineMode == .freeCanvas ? 0.45 : 1)
    }
  }
}
