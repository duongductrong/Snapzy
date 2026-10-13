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

  init(
    id: String,
    title: String,
    subtitle: String,
    systemImage: String,
    color: Color,
    url: URL
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.color = color
    self.url = url
  }

  func hash(into hasher: inout Hasher) { hasher.combine(id) }
  static func == (lhs: SponsorLink, rhs: SponsorLink) -> Bool { lhs.id == rhs.id }
}

enum SponsorLinks {
  static var all: [SponsorLink] {
    [
      SponsorLink(
        id: "github-sponsors",
        title: "GitHub Sponsors",
        subtitle: L10n.Sponsor.recurringSupport,
        systemImage: "heart.fill",
        color: .pink,
        url: URL(string: "https://github.com/sponsors/duongductrong")!
      ),
      SponsorLink(
        id: "ko-fi",
        title: "Ko-fi",
        subtitle: L10n.Sponsor.oneTimeTip,
        systemImage: "cup.and.saucer.fill",
        color: .orange,
        url: URL(string: "https://ko-fi.com/duongductrong")!
      ),
      SponsorLink(
        id: "paypal",
        title: "PayPal",
        subtitle: L10n.Sponsor.directSupport,
        systemImage: "creditcard.fill",
        color: .blue,
        url: URL(string: "https://www.paypal.com/paypalme/duongductrong")!
      ),
    ]
  }
}
