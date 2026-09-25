//
//  AboutContributor.swift
//  Snapzy
//
//  Static metadata for contributors displayed in About preferences.
//

import Foundation

struct AboutContributor: Identifiable, Hashable {
  let id: String
  let name: String
  let username: String

  var profileURL: URL {
    URL(string: "https://github.com/\(username)")!
  }

  init(name: String, username: String) {
    id = username
    self.name = name
    self.username = username
  }
}

extension AboutContributor {
  /// Featured contributors displayed in the default collapsed view.
  static let featured: [AboutContributor] = [
    AboutContributor(name: "Omar Shahine", username: "omarshahine"),
    AboutContributor(name: "Victor Xirau", username: "vxirau"),
    AboutContributor(name: "Yuri Chukhlib", username: "YuriNachos"),
    AboutContributor(name: "Yuan Zhang", username: "motoish"),
    AboutContributor(name: "tukuyomi032", username: "tukuyomil032"),
    AboutContributor(name: "Aurora", username: "lcopilot"),
    AboutContributor(name: "Jiawen Geng", username: "gengjiawen"),
    AboutContributor(name: "William Cachamwri", username: "williamcachamwri"),
  ]

  /// All-time contributors displayed when expanded.
  static let all: [AboutContributor] = [
    AboutContributor(name: "Omar Shahine", username: "omarshahine"),
    AboutContributor(name: "Victor Xirau", username: "vxirau"),
    AboutContributor(name: "tukuyomi032", username: "tukuyomil032"),
    AboutContributor(name: "Yuri Chukhlib", username: "YuriNachos"),
    AboutContributor(name: "Yuan Zhang", username: "motoish"),
    AboutContributor(name: "Aurora", username: "lcopilot"),
    AboutContributor(name: "Jiawen Geng", username: "gengjiawen"),
    AboutContributor(name: "HaomengKang", username: "menmer0859"),
    AboutContributor(name: "rv4no", username: "rv4no"),
    AboutContributor(name: "archie", username: "archibald-nice"),
    AboutContributor(name: "William Cachamwri", username: "williamcachamwri"),
    AboutContributor(name: "カワリミ人形", username: "kawarimidoll"),
    AboutContributor(name: "thanhthai3010", username: "thanhthai3010"),
    AboutContributor(name: "rvanhorn", username: "rvanhorn"),
    AboutContributor(name: "jmcubel", username: "jmcubel"),
    AboutContributor(name: "chk", username: "chkzz"),
    AboutContributor(name: "adrianocr", username: "adrianocr"),
    AboutContributor(name: "Stone", username: "st1020"),
    AboutContributor(name: "Ravi Maru", username: "RaviMaru20"),
    AboutContributor(name: "Qi Zhang", username: "singularitti"),
    AboutContributor(name: "Phoenix", username: "vnixx"),
    AboutContributor(name: "Oltian Kadriu", username: "okadriu"),
    AboutContributor(name: "Muhammed Mukhthar CM", username: "mukhtharcm"),
    AboutContributor(name: "Justin Jacob", username: "justsrc"),
    AboutContributor(name: "Jo", username: "j178"),
    AboutContributor(name: "Jean-Claude Joanna", username: "jjoanna2-debug"),
    AboutContributor(name: "Benjamin Dai", username: "BenjaminD2023"),
    AboutContributor(name: "5e3ru4o", username: "5e3ru4o"),
  ]
}
