// Compiled after actual repository models and camera functions, assembled on stdin.
// Camera paths, remapping, and interpolation come from production source unchanged.
@main
struct VideoEditorCameraCPUProbe {
  struct Measurement {
    let p50: Double
    let p95: Double
    let checksum: Double
  }

  @MainActor
  static func main() {
    let quick = CommandLine.arguments.dropFirst().contains("--quick")
    let repeatCount = quick ? 1 : 3
    let sampleCount = quick ? 12 : 60
    let buildCount = quick ? 6 : 30
    let cachedBatch = quick ? 120 : 1_020
    print("optimization=O warmup=3 repeats=\(repeatCount) samples=\(sampleCount) build_samples=\(buildCount) cached_batch=\(cachedBatch)")
    print("timings=CPU-only timing_threshold=none correctness=exact-path-and-camera-equality")

    var totalChecksum = 0.0
    for repetition in 1 ... repeatCount {
      print("repeat=\(repetition)")
      for seconds in [60.0, 600.0, 1_800.0] {
        let mouseSamples = (0 ... Int(seconds * 60)).map { index in
          let time = Double(index) / 60
          return RecordedMouseSample(
            time: time,
            normalizedX: 0.5 + 0.4 * sin(time * 0.7),
            normalizedY: 0.5 + 0.4 * cos(time * 0.5),
            isInsideCapture: index % 127 != 0
          )
        }
        let metadata = RecordingMetadata(
          captureSize: CGSize(width: 1_920, height: 1_080),
          samplesPerSecond: 60,
          mouseSamples: mouseSamples
        )
        let segment = ZoomSegment(
          startTime: seconds / 2,
          duration: 10,
          zoomLevel: 2.5,
          zoomType: .auto
        )
        let path = VideoEditorAutoFocusEngine.buildPath(from: metadata, segment: segment)
        precondition(!path.isEmpty, "Generated fixture must produce a camera path")
        let build = measure(count: buildCount) { index in
          var changed = segment
          changed.followSpeed = 0.5 + Double(index % 2) * 0.01
          let built = VideoEditorAutoFocusEngine.buildPath(from: metadata, segment: changed)
          return Double(built.count) + Double(built[built.count / 2].center.x)
        }
        let quality = measure(count: buildCount) { _ in
          let result = VideoEditorAutoFocusEngine.evaluatePathQuality(
            metadata: metadata, segment: segment, path: path
          )
          return result.meanError + result.lockAccuracy + result.visibilityRate + Double(result.sampleCount)
        }
        totalChecksum += build.checksum + quality.checksum
        print(String(
          format: "duration_s=%.0f metadata_samples=%d path_samples=%d build_p50_ms=%.6f build_p95_ms=%.6f quality_p50_ms=%.6f quality_p95_ms=%.6f",
          seconds, mouseSamples.count, path.count, build.p50, build.p95, quality.p50, quality.p95
        ))

        for clipCount in [1, 20, 100] {
          let placements = TimelineSequence.layout((0 ..< clipCount).map { index in
            TimelineClip(
              source: .primary,
              sourceDuration: seconds,
              sourceStart: seconds * Double(index) / Double(clipCount),
              sourceEnd: seconds * Double(index + 1) / Double(clipCount)
            )
          })
          let mapped = VideoEditorAutoFocusEngine.timelinePath(path, placements: placements)
          // Use the same positions in both paths, including transition boundaries.
          for index in 0 ..< sampleCount {
            let rebuilt = VideoEditorAutoFocusEngine.timelinePath(path, placements: placements)
            guard rebuilt == mapped,
                  camera(index: index, segment: segment, path: rebuilt, positions: sampleCount)
                    == camera(index: index, segment: segment, path: mapped, positions: sampleCount)
            else {
              fputs("Camera output mismatch: duration=\(seconds), clips=\(clipCount), index=\(index)\n", stderr)
              exit(1)
            }
          }
          let raw = measure(count: sampleCount) { index in
            let rebuilt = VideoEditorAutoFocusEngine.timelinePath(path, placements: placements)
            return cameraChecksum(index: index, segment: segment, path: rebuilt, positions: sampleCount)
          }
          // Batch is a multiple of the position count; raw and cached checksums
          // represent the same distribution while every inner call changes time.
          let cached = measure(count: sampleCount, batch: cachedBatch) { index in
            cameraChecksum(index: index, segment: segment, path: mapped, positions: sampleCount)
          }
          let checksumDelta = abs(raw.checksum - cached.checksum)
          guard checksumDelta < 0.000_000_01 else {
            fputs("Camera checksum mismatch: \(checksumDelta)\n", stderr)
            exit(1)
          }
          totalChecksum += raw.checksum + cached.checksum
          print(String(
            format: "duration_s=%.0f clips=%d mapped_samples=%d raw_p50_ms=%.6f raw_p95_ms=%.6f cached_p50_ms=%.6f cached_p95_ms=%.6f checksum_delta=%.12f exact_equal=true",
            seconds, clipCount, mapped.count, raw.p50, raw.p95, cached.p50, cached.p95, checksumDelta
          ))
        }
      }
    }
    print("result=PASS checksum=\(totalChecksum)")
  }

  @inline(never)
  @MainActor
  static func camera(
    index: Int, segment: ZoomSegment, path: [AutoFocusCameraSample], positions: Int
  ) -> VideoEditorCameraState {
    let fraction = Double(index % positions) / Double(positions - 1)
    return VideoEditorAutoFocusEngine.cameraState(
      at: segment.startTime + fraction * segment.duration,
      segment: segment,
      path: path,
      transitionDuration: 0.4
    )
  }

  @inline(never)
  @MainActor
  static func cameraChecksum(
    index: Int, segment: ZoomSegment, path: [AutoFocusCameraSample], positions: Int
  ) -> Double {
    let state = camera(index: index, segment: segment, path: path, positions: positions)
    return Double(state.center.x) + Double(state.center.y) + Double(state.zoomLevel)
  }

  @MainActor
  static func measure(count: Int, batch: Int = 1, work: (Int) -> Double) -> Measurement {
    for index in 0 ..< 3 { _ = work(index) }
    var timings: [Double] = []
    var checksum = 0.0
    for index in 0 ..< count {
      let start = DispatchTime.now().uptimeNanoseconds
      var partial = 0.0
      for inner in 0 ..< batch { partial += work(index * batch + inner) }
      let end = DispatchTime.now().uptimeNanoseconds
      checksum += partial / Double(batch)
      timings.append(Double(end - start) / 1_000_000 / Double(batch))
    }
    timings.sort()
    return Measurement(
      p50: timings[Int(Double(count - 1) * 0.5)],
      p95: timings[Int(Double(count - 1) * 0.95)],
      checksum: checksum
    )
  }
}
