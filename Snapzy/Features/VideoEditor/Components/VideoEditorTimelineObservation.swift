// Scoped invalidation for timeline surfaces. Recipe state remains authoritative.
import Combine
import Foundation

@MainActor
final class VideoEditorTimelineObservation: ObservableObject {
  nonisolated deinit {}

  enum Surface { case container, zoom, speed, clips, captions, camera }
  @Published private(set) var revision: UInt64 = 0
  private var subscriptions = Set<AnyCancellable>()

  init(state: VideoEditorState, surface: Surface) {
    // Zoom and speed blocks live on the structural axis, which a trim never moves
    // (clip slots are fixed): they only need the axis length, not every in/out change.
    // Their hover placeholder reads `isPlayableMaterial` live, so nothing goes stale.
    let clipsChange: AnyPublisher<Void, Never> = switch surface {
    case .zoom, .speed:
      state.$clips.map(TimelineSequence.duration).removeDuplicates().map { _ in () }.eraseToAnyPublisher()
    case .container, .clips, .captions, .camera:
      state.$clips.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
    }
    var changes: [AnyPublisher<Void, Never>] = [
      clipsChange,
      state.$duration.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
    ]
    switch surface {
    case .container:
      changes += [
        state.$frameThumbnails.map { _ in () }.eraseToAnyPublisher(),
        state.$isExtractingFrames.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
        state.$isZoomTrackVisible.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
        state.$isSpeedTrackVisible.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
        state.$captions.map(\.isEmpty).removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
        state.$recordingMetadata.map { _ in () }.eraseToAnyPublisher(),
      ]
    case .zoom:
      changes += [
        state.$zoomSegments.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
        state.$selectedZoomId.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
      ]
    case .speed:
      changes += [
        state.$speedSegments.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
        state.$selectedSpeedId.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
        state.$zoomSegments.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
      ]
    case .camera:
      changes += [state.$cameraSettings.map(\.hiddenRanges).removeDuplicates().map { _ in () }.eraseToAnyPublisher()]
    case .captions:
      changes += [state.$captions.removeDuplicates().map { _ in () }.eraseToAnyPublisher()]
    case .clips:
      changes += [
        state.$selectedClipId.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
        state.$canSplitAtPlayhead.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
        state.$frameThumbnails.map { _ in () }.eraseToAnyPublisher(),
        state.$isExtractingFrames.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
      ]
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
