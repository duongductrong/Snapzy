// Scoped invalidation for timeline surfaces. Recipe state remains authoritative.
import Combine
import Foundation

@MainActor
final class VideoEditorTimelineObservation: ObservableObject {
  enum Surface { case container, zoom, speed, clips }
  @Published private(set) var revision: UInt64 = 0
  private var subscriptions = Set<AnyCancellable>()

  init(state: VideoEditorState, surface: Surface) {
    var changes: [AnyPublisher<Void, Never>] = [
      state.$clips.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
      state.$duration.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
    ]
    switch surface {
    case .container:
      changes += [
        state.$frameThumbnails.map { _ in () }.eraseToAnyPublisher(),
        state.$isExtractingFrames.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
        state.$isZoomTrackVisible.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
        state.$isSpeedTrackVisible.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
      ]
    case .zoom:
      changes += [
        state.$zoomSegments.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
        state.$selectedZoomId.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
      ]
    case .speed:
      changes += [
        state.$speedSegments.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
        state.$selectedSpeedId.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
        state.$zoomSegments.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
      ]
    case .clips:
      changes += [
        state.$selectedClipId.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
        state.$canSplitAtPlayhead.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
        state.$frameThumbnails.map { _ in () }.eraseToAnyPublisher(),
        state.$isExtractingFrames.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
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
