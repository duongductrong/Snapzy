//
//  MockupTransformModifier.swift
//  Snapzy
//
//  View modifier for applying 3D mockup transforms
//

import SwiftUI

/// View modifier that applies 3D transforms when mockup tool is active
struct MockupTransformModifier: ViewModifier {
    @ObservedObject var state: AnnotateState
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .clipShape(RoundedRectangle(cornerRadius: state.mockupCornerRadius, style: .continuous))
                .rotation3DEffect(
                    .degrees(state.mockupRotationY),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .center,
                    anchorZ: 0,
                    perspective: state.mockupPerspective
                )
                .rotation3DEffect(
                    .degrees(state.mockupRotationX),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .center,
                    anchorZ: 0,
                    perspective: state.mockupPerspective
                )
                .rotation3DEffect(
                    .degrees(state.mockupRotationZ),
                    axis: (x: 0, y: 0, z: 1),
                    anchor: .center
                )
                .shadow(
                    color: .black.opacity(state.mockupShadowIntensity),
                    radius: state.mockupShadowRadius,
                    x: state.mockupShadowOffsetX,
                    y: state.mockupShadowOffsetY
                )
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: state.mockupRotationX)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: state.mockupRotationY)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: state.mockupRotationZ)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: state.mockupPerspective)
        } else {
            content
        }
    }
}
