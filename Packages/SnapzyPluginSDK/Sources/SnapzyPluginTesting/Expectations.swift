import Foundation
import SnapzyPluginAPI
import SnapzyPluginSDK

public extension FakeHost {
  func assertCalled(service: String) -> Bool {
    calls.contains { $0.service == service }
  }

  func callCount(for service: String) -> Int {
    calls.filter { $0.service == service }.count
  }
}
