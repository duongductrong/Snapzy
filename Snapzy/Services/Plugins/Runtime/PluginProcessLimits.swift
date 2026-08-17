import Darwin
import Foundation

enum PluginProcessLimits {
  static let defaultDeadline: Duration = .seconds(120)
  static let longRunningDeadline: Duration = .seconds(1_800)
  static let defaultMemoryLimitBytes: UInt64 = 512 * 1024 * 1024

  /// Returns current resident memory usage (RSS in bytes) for a given pid, or nil if unavailable.
  static func residentMemoryBytes(for pid: pid_t) -> UInt64? {
    var info = proc_taskallinfo()
    let size = Int32(MemoryLayout<proc_taskallinfo>.size)
    let result = proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, size)
    guard result == size else { return nil }
    return UInt64(info.ptinfo.pti_resident_size)
  }
}
