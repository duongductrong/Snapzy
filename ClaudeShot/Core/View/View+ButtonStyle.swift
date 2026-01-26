//
//  View+ButtonStyle.swift
//  ClaudeShot
//
//  Reusable button style modifier for any View
//

import SwiftUI

/// ViewModifier that applies button-like styling to any view
struct ButtonStyleModifier: ViewModifier {
    var backgroundColor: Color
    var foregroundColor: Color
    var strokeColor: Color?
    var strokeWidth: CGFloat
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat
    var cornerRadius: CGFloat
    var corners: RectCorner

    func body(content: Content) -> some View {
        content
            .foregroundColor(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedCornerShape(radius: cornerRadius, corners: corners)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedCornerShape(radius: cornerRadius, corners: corners)
                    .stroke(strokeColor ?? .clear, lineWidth: strokeColor != nil ? strokeWidth : 0)
            )
    }
}

extension View {
    /// Apply button styling to any view
    /// - Parameters:
    ///   - backgroundColor: Background color (default: .clear)
    ///   - foregroundColor: Text/content color (default: .primary)
    ///   - strokeColor: Border color (optional)
    ///   - strokeWidth: Border width (default: 1)
    ///   - horizontalPadding: Horizontal padding (default: 16)
    ///   - verticalPadding: Vertical padding (default: 8)
    ///   - cornerRadius: Corner radius (default: 8)
    ///   - corners: Which corners to round (default: .allCorners)
    func button(
        backgroundColor: Color = .clear,
        foregroundColor: Color = .primary,
        strokeColor: Color? = nil,
        strokeWidth: CGFloat = 1,
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 8,
        cornerRadius: CGFloat = 8,
        corners: RectCorner = .allCorners
    ) -> some View {
        modifier(ButtonStyleModifier(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            cornerRadius: cornerRadius,
            corners: corners
        ))
    }
}
