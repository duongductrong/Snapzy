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
    VStack(alignment: .leading, spacing: Spacing.md) {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        SidebarSectionHeader(title: L10n.Combine.mode)
        AnnotateCombineModePicker(state: state)
      }

      Divider().background(Color(nsColor: .separatorColor))

      directionSection

      Divider().background(Color(nsColor: .separatorColor))

      imageOrderSection

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

      Divider().background(Color(nsColor: .separatorColor))
    }
  }

  private var imageOrderSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack {
        SidebarSectionHeader(title: L10n.Combine.images)
        Spacer()
        Text("\(state.combineImageCount)")
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)
      }

      ForEach(0 ..< state.combineImageCount, id: \.self) { index in
        HStack(spacing: Spacing.xs) {
          Image(systemName: "photo")
            .foregroundColor(.accentColor)
          Text(L10n.Combine.image(index + 1))
            .font(Typography.labelSmall)
          Spacer()
          Button {
            state.moveCombineImage(at: index, by: -1)
          } label: {
            Image(systemName: "chevron.up")
          }
          .buttonStyle(.borderless)
          .disabled(index == 0)
          .help(L10n.Combine.moveEarlier)

          Button {
            state.moveCombineImage(at: index, by: 1)
          } label: {
            Image(systemName: "chevron.down")
          }
          .buttonStyle(.borderless)
          .disabled(index == state.combineImageCount - 1)
          .help(L10n.Combine.moveLater)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: Size.radiusSm)
            .fill(SidebarColors.itemDefault)
        )
      }
    }
  }

  private var directionSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack {
        SidebarSectionHeader(title: L10n.Combine.arrangement)
        Spacer()
        if state.combineDirection == .smart {
          Text(state.combineResolvedDirection == .horizontal ? L10n.Combine.horizontal : L10n.Combine.vertical)
            .font(Typography.labelSmall)
            .foregroundColor(SidebarColors.labelSecondary)
        }
      }

      HStack(spacing: Spacing.xs) {
        directionButton(.smart, title: L10n.Combine.smart, icon: "sparkles")
        directionButton(.horizontal, title: L10n.Combine.horizontal, icon: "rectangle.split.3x1")
        directionButton(.vertical, title: L10n.Combine.vertical, icon: "rectangle.split.1x2")
      }
    }
    .disabled(state.combineMode == .freeCanvas)
    .opacity(state.combineMode == .freeCanvas ? 0.45 : 1)
  }

  private func directionButton(
    _ direction: CombineImagesDirection,
    title: String,
    icon: String
  ) -> some View {
    Button {
      state.setCombineDirection(direction)
    } label: {
      VStack(spacing: 4) {
        Image(systemName: icon)
          .font(.system(size: 12, weight: .medium))
        Text(title)
          .font(Typography.labelSmall)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, minHeight: 38)
      .foregroundColor(state.combineDirection == direction ? .white : SidebarColors.labelSecondary)
      .background(
        RoundedRectangle(cornerRadius: Size.radiusSm)
          .fill(state.combineDirection == direction ? Color.accentColor.opacity(0.75) : SidebarColors.itemDefault)
      )
      .overlay(
        RoundedRectangle(cornerRadius: Size.radiusSm)
          .stroke(state.combineDirection == direction ? Color.accentColor : Color.clear, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }
}
