//
//  SponsorLinks.swift
//  Snapzy
//
//  Shared sponsor destinations used across onboarding and preferences.
//

import Foundation
import SwiftUI

struct SponsorLink: Identifiable, Hashable {
  let id: String
  let title: String
  let subtitle: String
  let systemImage: String
  let color: Color
  let url: URL

  func hash(into hasher: inout Hasher) { hasher.combine(id) }
  static func == (lhs: SponsorLink, rhs: SponsorLink) -> Bool { lhs.id == rhs.id }
}

enum SponsorLinks {
  static let all: [SponsorLink] = [
    SponsorLink(
      id: "github-sponsors",
      title: "GitHub Sponsors",
      subtitle: "Recurring support",
      systemImage: "heart.fill",
      color: .pink,
      url: URL(string: "https://github.com/sponsors/duongductrong")!
    ),
    SponsorLink(
      id: "ko-fi",
      title: "Ko-fi",
      subtitle: "One-time tip",
      systemImage: "cup.and.saucer.fill",
      color: .orange,
      url: URL(string: "https://ko-fi.com/duongductrong")!
    ),
    SponsorLink(
      id: "paypal",
      title: "PayPal",
      subtitle: "Direct support",
      systemImage: "creditcard.fill",
      color: .blue,
      url: URL(string: "https://www.paypal.com/paypalme/duongductrong")!
    ),
  ]
}
