// Scoped invalidation for timeline surfaces. Recipe state remains authoritative.
import Combine
import Foundation

@MainActor
final class VideoEditorTimelineObservation: ObservableObject {
  enum Surface { case container, zoom, speed, clips, audio, captions, camera, text }
  @Published private(set) var revision: UInt64 = 0
  private var subscriptions = Set<AnyCancellable>()

  /// Explicit and nonisolated: avoids macOS 13-15 swift_task_deinitOnExecutor abort (#668).
  nonisolated deinit {}

  init(state: VideoEditorState, surface: Surface) {
    // Zoom, speed, text, and audio blocks live on the structural axis: they only need
    // the axis length from `clips`, not every clip selection or frame-extraction tick.
    let clipsChange: AnyPublisher<Void, Never> = switch surface {
    case .zoom, .speed, .text, .audio:
      state.$clips.map(TimelineSequence.duration).removeDuplicates().map { _ in () }.eraseToAnyPublisher()
    case .container, .clips, .captions, .camera:
      state.$clips.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
    }
    var changes: [AnyPublisher<Void, Never>] = [
      clipsChange,
      state.$duration.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
      state.$audioClips
        .map { $0.map(\.timelineEnd).max() ?? 0 }
        .removeDuplicates()
        .map { _ in () }
        .eraseToAnyPublisher(),
    ]
    switch surface {
    case .container:
      changes.append(state.$frameThumbnails.map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$isExtractingFrames.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$isZoomTrackVisible.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$isSpeedTrackVisible.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$captions.map(\.isEmpty).removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      let textLaneChange: AnyPublisher<Void, Never> = state.$textOverlays
        .map { ($0.isEmpty, TextTimelineLaneLayout.laneCount(for: $0)) }
        .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
        .map { _ in () }
        .eraseToAnyPublisher()
      changes.append(textLaneChange)
      changes.append(state.$minimumTextLanes.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      let audioLaneChange: AnyPublisher<Void, Never> = state.$audioClips
        .map { AudioTimelineLaneLayout.laneCount(for: $0) }
        .removeDuplicates()
        .map { _ in () }
        .eraseToAnyPublisher()
      changes.append(audioLaneChange)
      changes.append(state.$minimumAudioLanes.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$recordingMetadata.map { _ in () }.eraseToAnyPublisher())
    case .zoom:
      changes.append(state.$zoomSegments.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$selectedZoomId.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
    case .speed:
      changes.append(state.$speedSegments.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$selectedSpeedId.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$zoomSegments.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
    case .camera:
      changes.append(state.$cameraSettings.map(\.hiddenRanges).removeDuplicates().map { _ in () }.eraseToAnyPublisher())
    case .captions:
      changes.append(state.$captions.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$selectedCaptionId.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$selectedCaptionIds.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
    case .text:
      changes.append(state.$textOverlays.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$selectedTextOverlayId.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$selectedTextOverlayIds.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$minimumTextLanes.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
    case .clips:
      changes.append(state.$selectedClipId.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$frameThumbnails.map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$isExtractingFrames.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
    case .audio:
      changes.append(state.$audioClips.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$selectedAudioClipId.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$selectedAudioClipIds.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$minimumAudioLanes.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$mutedAudioLanes.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$exportSettings.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$isMuted.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
      changes.append(state.$audioTrackRoles.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
    }
    // Published emits before storage (willSet). Defer to the next main queue
    // turn and coalesce the fields belonging to one mutation, then views read the
    // committed recipe and its synchronously invalidated caches.
    Publishers.MergeMany(changes)
      .debounce(for: .zero, scheduler: DispatchQueue.main)
      .sink { [weak self] in self?.revision &+= 1 }
      .store(in: &subscriptions)
  }
}
