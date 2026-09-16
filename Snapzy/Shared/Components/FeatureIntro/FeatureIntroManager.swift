//
//  FeatureIntroManager.swift
//  Snapzy
//
//  Orchestrates loading JSON campaigns and displaying them.
//

import AppKit
import Foundation

@MainActor
public final class FeatureIntroManager {
  public static let shared = FeatureIntroManager()
  
  private var windowController: FeatureIntroWindowController?
  
  private init() {}
  
  /// Loads the configuration from whats_new.json
  private func loadRootConfig() -> FeatureIntroRootConfig? {
    guard let url = Bundle.main.url(forResource: "whats_new", withExtension: "json"),
          let data = try? Data(contentsOf: url) else {
      return nil
    }
    
    do {
      return try JSONDecoder().decode(FeatureIntroRootConfig.self, from: data)
    } catch {
      print("Failed to decode whats_new.json: \(error)")
      return nil
    }
  }
  
  /// Returns the first enabled campaign that the user hasn't seen yet.
  public func getPendingCampaign() -> FeatureIntroCampaign? {
    guard let root = loadRootConfig() else { return nil }
    
    return root.campaigns.first { campaign in
      campaign.isEnabled && !FeatureIntroTracker.shared.hasSeen(campaignId: campaign.id)
    }
  }
  
  /// Displays the given campaign in the floating window.
  public func showCampaign(_ campaign: FeatureIntroCampaign) {
    guard windowController == nil else {
      windowController?.show()
      return
    }
    
    let screens: [FeatureIntroScreen] = campaign.screens.map { config in
      var actionClosure: (() -> Void)? = nil
      
      // Map action IDs to internal closures
      if config.actionId == "start_smart_capture" {
        actionClosure = { SmartElementCaptureController.shared.startCapture() }
      }
      
      return FeatureIntroScreen(
        id: config.id,
        title: config.title,
        description: config.description,
        systemImage: config.systemImage,
        customImageName: config.customImageName,
        shortcutKeys: config.shortcutKeys,
        actionTitle: config.actionTitle,
        action: actionClosure,
        nextActionTitle: config.nextActionTitle
      )
    }
    
    let controller = FeatureIntroWindowController(screens: screens)
    self.windowController = controller
    
    // Clean up reference when window closes
    NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: controller.window,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.windowController = nil
      }
    }
    
    FeatureIntroTracker.shared.markAsSeen(campaignId: campaign.id)
    controller.show()
  }
}
