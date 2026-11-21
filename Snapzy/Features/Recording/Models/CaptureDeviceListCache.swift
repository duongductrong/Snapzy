//
//  CaptureDeviceListCache.swift
//  Snapzy
//
//  Caches AVCaptureDevice discovery results. SwiftUI toolbar menus ask for the device
//  list on every body evaluation; each DiscoverySession call enumerates CoreMediaIO
//  devices synchronously on the main thread and can block there. The list only
//  changes when a device connects or disconnects, so it is rebuilt then.
//

import AVFoundation
import Foundation

@MainActor
enum CaptureDeviceListCache {
  private static var lists: [AVMediaType: [AVCaptureDevice]] = [:]
  private static var observers: [NSObjectProtocol] = []

  static func devices(for mediaType: AVMediaType, discover: () -> [AVCaptureDevice]) -> [AVCaptureDevice] {
    installObserversIfNeeded()
    if let cached = lists[mediaType] { return cached }
    let devices = discover()
    lists[mediaType] = devices
    return devices
  }

  static func invalidate() {
    lists.removeAll()
  }

  private static func installObserversIfNeeded() {
    guard observers.isEmpty else { return }
    let center = NotificationCenter.default
    observers = [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification].map {
      center.addObserver(forName: $0, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { invalidate() }
      }
    }
  }
}
