//
//  QuickAccessCardSurface.swift
//  Snapzy
//
//  The Quick Access card's chrome: rounded clip, backdrop, GPU-cached shadow
//  and hairline stroke. Shared by the stack card and its edge peek (#591) so
//  a collapsed card looks exactly like the card it came from.
//

import AppKit
import SwiftUI

struct QuickAccessCardSurface: ViewModifier {
  var cornerRadius: CGFloat = Radius.card

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    content
      .clipShape(shape)
      .contentShape(shape)
      .background(shape.fill(Color.black.opacity(0.1)))
      // GPU-cached drop shadow (furthest back). Replaces per-frame SwiftUI `.shadow()`
      // blur that lagged when many stacked cards recomposited during capture-area mode.
      .background(QuickAccessCardShadowView(cornerRadius: cornerRadius))
      .overlay(shape.stroke(Color.white.opacity(0.2), lineWidth: 1))
  }
}

extension View {
  func quickAccessCardSurface(cornerRadius: CGFloat = Radius.card) -> some View {
    modifier(QuickAccessCardSurface(cornerRadius: cornerRadius))
  }
}

/// Card thumbnail fill, identical crop to the stack card.
struct QuickAccessCardThumbnail: View {
  let image: NSImage
  let size: CGSize

  var body: some View {
    // Clipped scaled-to-fill images can still expose their hidden area to hit
    // testing, so the thumbnail stays decorative and the card owns interaction.
    Image(nsImage: image)
      .resizable()
      .aspectRatio(contentMode: .fill)
      .frame(width: size.width, height: size.height)
      .clipped()
      .contentShape(Rectangle())
      .allowsHitTesting(false)
  }
}
