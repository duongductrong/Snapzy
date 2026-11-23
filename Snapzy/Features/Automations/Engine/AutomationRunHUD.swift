//
//  AutomationRunHUD.swift
//  Snapzy
//
//  Small bottom-center panel shown when a run takes longer than 1.5 s: the
//  automation, its current step and a Cancel button. Non-activating, so it
//  never takes focus from the app the user is working in.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class AutomationRunHUDController {
  static let shared = AutomationRunHUDController()

  private static let showDelay: UInt64 = 1_500_000_000

  private final class Model: ObservableObject {
    @Published var name = ""
    @Published var step = ""
  }

  private struct ActiveRun {
    let name: String
    var step: String
    var showTask: Task<Void, Never>?
  }

  private var runs: [UUID: ActiveRun] = [:]
  private var displayedRunID: UUID?
  private var panel: NSPanel?
  private let model = Model()

  func handle(_ update: AutomationRunUpdate) {
    switch update {
    case .started(let runID, let name):
      let task = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: Self.showDelay)
        guard !Task.isCancelled else { return }
        self?.show(runID)
      }
      runs[runID] = ActiveRun(name: name, step: "", showTask: task)
    case .step(let runID, let title):
      runs[runID]?.step = title
      if displayedRunID == runID { model.step = title }
    case .finished(let runID):
      runs.removeValue(forKey: runID)?.showTask?.cancel()
      if displayedRunID == runID {
        displayedRunID = nil
        if let next = runs.keys.first, runs[next]?.showTask == nil {
          show(next)
        } else {
          hide()
        }
      }
    }
  }

  private func show(_ runID: UUID) {
    guard var run = runs[runID] else { return }
    run.showTask = nil
    runs[runID] = run
    displayedRunID = runID
    model.name = run.name
    model.step = run.step
    let panel = panel ?? makePanel()
    self.panel = panel
    position(panel)
    panel.orderFrontRegardless()
  }

  private func hide() {
    panel?.orderOut(nil)
  }

  private func cancelDisplayedRun() {
    guard let runID = displayedRunID else { return }
    AutomationRunner.shared.cancel(runID: runID)
  }

  private func makePanel() -> NSPanel {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 56),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.contentView = NSHostingView(rootView: AutomationRunHUDView(model: model) { [weak self] in
      self?.cancelDisplayedRun()
    })
    return panel
  }

  private func position(_ panel: NSPanel) {
    guard let screen = NSScreen.main else { return }
    let frame = screen.visibleFrame
    let size = panel.frame.size
    panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 40))
  }

  private struct AutomationRunHUDView: View {
    @ObservedObject var model: Model
    let onCancel: () -> Void

    var body: some View {
      HStack(spacing: 10) {
        ProgressView()
          .controlSize(.small)
        VStack(alignment: .leading, spacing: 1) {
          Text(model.name)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
          if !model.step.isEmpty {
            Text(model.step)
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 8)
        Button(L10n.Common.cancel, action: onCancel)
          .controlSize(.small)
      }
      .padding(.horizontal, 14)
      .frame(width: 320, height: 56)
      .background(.regularMaterial, in: Radius.rect(Radius.card))
      .accessibilityElement(children: .combine)
    }
  }
}
