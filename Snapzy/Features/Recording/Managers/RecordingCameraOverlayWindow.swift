//
//  RecordingCameraOverlayWindow.swift
//  Snapzy
//
//  Camera preview overlay captured with the screen recording.
//

import AppKit
@preconcurrency import AVFoundation
import QuartzCore

struct RecordingCameraDevice: Identifiable, Equatable {
  static let systemDefaultID = "system-default"

  let id: String
  let name: String
  let isSystemDefault: Bool
  let isUnavailable: Bool
  let isContinuityCamera: Bool

  var displayName: String {
    if isSystemDefault {
      return L10n.Camera.systemDefault
    }
    if isUnavailable {
      return L10n.Camera.unavailable
    }
    if isContinuityCamera {
      return "\(name) (\(L10n.Camera.continuity))"
    }
    return name
  }

  static var systemDefault: RecordingCameraDevice {
    RecordingCameraDevice(
      id: systemDefaultID,
      name: L10n.Camera.systemDefault,
      isSystemDefault: true,
      isUnavailable: false,
      isContinuityCamera: false
    )
  }
}

enum RecordingCameraDeviceProvider {
  static func storedDeviceID(defaults: UserDefaults = .standard) -> String {
    let value = defaults.string(forKey: PreferencesKeys.recordingCameraDeviceID)
    guard let value, !value.isEmpty else { return RecordingCameraDevice.systemDefaultID }
    return value
  }

  static func normalizedCaptureDeviceID(_ deviceID: String?) -> String? {
    guard let deviceID, !deviceID.isEmpty, deviceID != RecordingCameraDevice.systemDefaultID else {
      return nil
    }
    return deviceID
  }

  static func availableDevices(selectedDeviceID: String? = nil) -> [RecordingCameraDevice] {
    var devices = [RecordingCameraDevice.systemDefault]
    let mappedDevices = captureDevices().map {
      RecordingCameraDevice(
        id: $0.uniqueID,
        name: $0.localizedName,
        isSystemDefault: false,
        isUnavailable: false,
        isContinuityCamera: $0.isContinuityCamera
      )
    }

    var seenIDs = Set(devices.map(\.id))
    for device in mappedDevices where seenIDs.insert(device.id).inserted {
      devices.append(device)
    }

    if let selectedDeviceID = normalizedCaptureDeviceID(selectedDeviceID),
       !seenIDs.contains(selectedDeviceID) {
      devices.append(
        RecordingCameraDevice(
          id: selectedDeviceID,
          name: L10n.Camera.unavailable,
          isSystemDefault: false,
          isUnavailable: true,
          isContinuityCamera: false
        )
      )
    }

    return devices
  }

  static func captureDevice(matching deviceID: String?) -> AVCaptureDevice? {
    if let deviceID = normalizedCaptureDeviceID(deviceID) {
      return captureDevices().first(where: { $0.uniqueID == deviceID })
    }

    return AVCaptureDevice.default(for: .video) ?? captureDevices().first
  }

  static func requestAccessIfNeeded() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      return true
    case .notDetermined:
      return await AVCaptureDevice.requestAccess(for: .video)
    case .denied, .restricted:
      return false
    @unknown default:
      return false
    }
  }

  private static func captureDevices() -> [AVCaptureDevice] {
    let deviceTypes: [AVCaptureDevice.DeviceType] = if #available(macOS 14.0, *) {
      [.builtInWideAngleCamera, .continuityCamera, .external, .deskViewCamera]
    } else {
      [.builtInWideAngleCamera, .externalUnknown, .deskViewCamera]
    }

    let session = AVCaptureDevice.DiscoverySession(
      deviceTypes: deviceTypes,
      mediaType: .video,
      position: .unspecified
    )
    return session.devices.sorted { lhs, rhs in
      if lhs.isContinuityCamera != rhs.isContinuityCamera {
        return lhs.isContinuityCamera
      }
      return lhs.localizedName.localizedCaseInsensitiveCompare(rhs.localizedName) == .orderedAscending
    }
  }
}

private enum RecordingCameraOverlayError: Error {
  case noDevice
  case cannotAddInput
}

private final nonisolated class RecordingCameraCaptureSession: @unchecked Sendable {
  let session = AVCaptureSession()

  private let deviceID: String
  private let availabilityHandler: @MainActor @Sendable (Bool) -> Void
  private let sessionQueue = DispatchQueue(
    label: "com.trongduong.snapzy.camera.session",
    qos: .userInitiated
  )
  private var notificationTokens: [NSObjectProtocol] = []
  private var isStopped = true

  init(
    device: AVCaptureDevice,
    availabilityHandler: @escaping @MainActor @Sendable (Bool) -> Void
  ) throws {
    deviceID = device.uniqueID
    self.availabilityHandler = availabilityHandler

    let input = try AVCaptureDeviceInput(device: device)
    guard session.canAddInput(input) else {
      throw RecordingCameraOverlayError.cannotAddInput
    }

    session.beginConfiguration()
    session.sessionPreset = .high
    session.addInput(input)
    session.commitConfiguration()

    observeCameraState()
  }

  deinit {
    for token in notificationTokens {
      NotificationCenter.default.removeObserver(token)
    }
  }

  func start() {
    sessionQueue.async { [self] in
      isStopped = false
      if !session.isRunning {
        session.startRunning()
      }
      publishAvailability(session.isRunning)
    }
  }

  func stop() {
    sessionQueue.async { [self] in
      isStopped = true
      if session.isRunning {
        session.stopRunning()
      }
    }
  }

  private func observeCameraState() {
    let center = NotificationCenter.default
    notificationTokens = [
      center.addObserver(
        forName: AVCaptureDevice.wasDisconnectedNotification,
        object: nil,
        queue: nil
      ) { [weak self] notification in
        guard let self,
              let device = notification.object as? AVCaptureDevice,
              device.uniqueID == deviceID else { return }
        publishAvailability(false)
      },
      center.addObserver(
        forName: AVCaptureDevice.wasConnectedNotification,
        object: nil,
        queue: nil
      ) { [weak self] notification in
        guard let self,
              let device = notification.object as? AVCaptureDevice,
              device.uniqueID == deviceID else { return }
        reconnect(to: device)
      },
      center.addObserver(
        forName: AVCaptureSession.wasInterruptedNotification,
        object: session,
        queue: nil
      ) { [weak self] _ in
        self?.publishAvailability(false)
      },
      center.addObserver(
        forName: AVCaptureSession.interruptionEndedNotification,
        object: session,
        queue: nil
      ) { [weak self] _ in
        self?.restartIfNeeded()
      },
      center.addObserver(
        forName: AVCaptureSession.runtimeErrorNotification,
        object: session,
        queue: nil
      ) { [weak self] notification in
        guard let self else { return }
        publishAvailability(false)
        if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError,
           error.code == -11819 { // AVErrorMediaServicesWereReset
          restartIfNeeded()
        }
      },
    ]
  }

  private func reconnect(to device: AVCaptureDevice) {
    sessionQueue.async { [self] in
      guard !isStopped else { return }

      session.beginConfiguration()
      for input in session.inputs {
        session.removeInput(input)
      }

      do {
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
          session.commitConfiguration()
          publishAvailability(false)
          return
        }
        session.addInput(input)
        session.commitConfiguration()
        restartIfNeededOnSessionQueue()
      } catch {
        session.commitConfiguration()
        publishAvailability(false)
      }
    }
  }

  private func restartIfNeeded() {
    sessionQueue.async { [self] in
      restartIfNeededOnSessionQueue()
    }
  }

  private func restartIfNeededOnSessionQueue() {
    guard !isStopped else { return }
    if !session.isRunning {
      session.startRunning()
    }
    publishAvailability(session.isRunning)
  }

  private func publishAvailability(_ isAvailable: Bool) {
    Task { @MainActor [availabilityHandler] in
      availabilityHandler(isAvailable)
    }
  }
}

@MainActor
final class RecordingCameraOverlayWindow: NSPanel {
  nonisolated static let maximumWidth: CGFloat = 280
  nonisolated static let minimumWidth: CGFloat = 120
  nonisolated static let widthFraction: CGFloat = 0.28
  nonisolated static let aspectRatio: CGFloat = 16.0 / 9.0
  nonisolated static let edgeInset: CGFloat = RecordingCameraOverlayPlacement.defaultEdgeInset

  private let cameraSession: RecordingCameraCaptureSession
  private let recordingRect: CGRect
  private var isDragging = false
  private var dragOffset = CGPoint.zero

  init(recordingRect: CGRect, deviceID: String?) throws {
    guard let device = RecordingCameraDeviceProvider.captureDevice(matching: deviceID) else {
      throw RecordingCameraOverlayError.noDevice
    }

    let previewView = RecordingCameraPreviewView()
    let cameraSession = try RecordingCameraCaptureSession(device: device) { [weak previewView] isAvailable in
      previewView?.setCameraAvailable(isAvailable)
    }
    self.cameraSession = cameraSession
    self.recordingRect = recordingRect

    super.init(
      contentRect: Self.overlayFrame(in: recordingRect),
      // While a recording runs Snapzy is a background app, so a click on a
      // plain window makes AppKit run the app-activation path and look for a
      // window to make key — which this overlay refuses. `.nonactivatingPanel`
      // takes the overlay out of that path entirely: the click moves the
      // preview without activating Snapzy or touching key-window state.
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    configureWindow()
    previewView.attach(session: cameraSession.session)
    contentView = previewView
  }

  var overlayWindowID: CGWindowID {
    CGWindowID(windowNumber)
  }

  func startPreview() {
    orderFrontRegardless()
    cameraSession.start()
  }

  /// The overlay owns the entire left-button gesture. Routing it here instead
  /// of through the content view keeps AppKit's default mouse handling — the
  /// window-move machinery, the title-bar double-click action, first-responder
  /// changes — out of the drag completely; each of those paths can answer a
  /// borderless, non-key window with the system alert sound.
  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .leftMouseDown:
      beginDragging(with: event)
    case .leftMouseDragged where isDragging:
      continueDragging(with: event)
    case .leftMouseUp where isDragging:
      endDragging()
    default:
      super.sendEvent(event)
    }
  }

  private func beginDragging(with event: NSEvent) {
    let mouseLocation = convertPoint(toScreen: event.locationInWindow)
    dragOffset = CGPoint(
      x: mouseLocation.x - frame.minX,
      y: mouseLocation.y - frame.minY
    )
    isDragging = true
    NSCursor.closedHand.set()
  }

  private func continueDragging(with event: NSEvent) {
    let mouseLocation = convertPoint(toScreen: event.locationInWindow)
    updateDragOrigin(
      CGPoint(
        x: mouseLocation.x - dragOffset.x,
        y: mouseLocation.y - dragOffset.y
      )
    )
  }

  private func endDragging() {
    guard isDragging else { return }
    isDragging = false
    NSCursor.openHand.set()
  }

  func updateDragOrigin(_ proposedOrigin: CGPoint) {
    let resolvedOrigin = RecordingCameraOverlayPlacement.resolvedOrigin(
      for: proposedOrigin,
      recordingRect: recordingRect,
      overlaySize: frame.size,
      edgeInset: Self.edgeInset
    )

    // Keep the window frame in lockstep with the pointer while the button is
    // held. An asynchronous NSWindow animation can leave WindowServer hit
    // testing a stale frame and retarget the next drag/up event to another
    // window. The resolved origin still applies the same clamp and snap rules.
    setFrameOrigin(resolvedOrigin)
  }

  override func close() {
    endDragging()
    cameraSession.stop()
    super.close()
  }

  nonisolated static func overlayFrame(in recordingRect: CGRect) -> CGRect {
    let usableWidth = max(1, recordingRect.width - edgeInset * 2)
    let usableHeight = max(1, recordingRect.height - edgeInset * 2)

    var width = min(maximumWidth, max(minimumWidth, recordingRect.width * widthFraction))
    var height = width / aspectRatio

    if width > usableWidth {
      width = usableWidth
      height = width / aspectRatio
    }
    if height > usableHeight {
      height = usableHeight
      width = height * aspectRatio
    }

    let horizontalInset = min(edgeInset, max(0, (recordingRect.width - width) / 2))
    let verticalInset = min(edgeInset, max(0, (recordingRect.height - height) / 2))
    return CGRect(
      x: recordingRect.maxX - horizontalInset - width,
      y: recordingRect.minY + verticalInset,
      width: width,
      height: height
    )
  }

  private func configureWindow() {
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isReleasedWhenClosed = false
    level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    isFloatingPanel = true
    becomesKeyOnlyIfNeeded = true
    // Panels hide on deactivation by default; the overlay has to stay visible
    // for the whole recording no matter which app is frontmost.
    hidesOnDeactivate = false
    // `sendEvent` owns the mouse-down/dragged/up sequence, so AppKit keeps
    // tracking this window after the pointer leaves its frame. Disable the
    // server-side window drag path as well.
    isMovable = false
    isMovableByWindowBackground = false
    ignoresMouseEvents = false
    sharingType = .readOnly
  }

  override var canBecomeKey: Bool {
    false
  }

  override var canBecomeMain: Bool {
    false
  }
}

private final class RecordingCameraPreviewView: NSView {
  private let previewLayer = AVCaptureVideoPreviewLayer()
  private let unavailableLabel = NSTextField(wrappingLabelWithString: L10n.Camera.disconnected)

  init() {
    super.init(frame: .zero)

    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor
    layer?.cornerRadius = 18
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    layer?.borderWidth = 2
    layer?.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor

    previewLayer.videoGravity = .resizeAspectFill
    layer?.addSublayer(previewLayer)

    unavailableLabel.alignment = .center
    unavailableLabel.textColor = .white
    unavailableLabel.font = .systemFont(ofSize: 13, weight: .medium)
    unavailableLabel.isHidden = true
    unavailableLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(unavailableLabel)
    NSLayoutConstraint.activate([
      unavailableLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      unavailableLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      unavailableLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
      unavailableLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
    ])
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) not supported")
  }

  func attach(session: AVCaptureSession) {
    previewLayer.session = session
  }

  func setCameraAvailable(_ isAvailable: Bool) {
    previewLayer.isHidden = !isAvailable
    unavailableLabel.isHidden = isAvailable
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    previewLayer.frame = bounds
    CATransaction.commit()
  }

  override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
    true
  }

  /// Prevent AppKit from treating a mouse-down in this view as a native window drag.
  override var mouseDownCanMoveWindow: Bool {
    false
  }

  override func resetCursorRects() {
    super.resetCursorRects()
    addCursorRect(bounds, cursor: .openHand)
  }

  override func hitTest(_: NSPoint) -> NSView? {
    self
  }
}
