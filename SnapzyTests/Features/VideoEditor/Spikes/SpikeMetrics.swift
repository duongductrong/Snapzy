//
//  SpikeMetrics.swift
//  SnapzyTests
//
//  CPU counters shared by the Studio phase-0 spike harnesses.
//

import Darwin
import Foundation

enum SpikeMetrics {
  /// User + system CPU seconds consumed by this process so far.
  static func processCPUTime() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
    return seconds(usage.ru_utime) + seconds(usage.ru_stime)
  }

  /// Machine-wide CPU ticks (all cores): busy = user + system + nice.
  /// Captures out-of-process work (VTDecoderXPCService, WindowServer) too.
  static func machineTicks() -> (busy: UInt64, total: UInt64) {
    var info = host_cpu_load_info()
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
    _ = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
      }
    }
    let t = info.cpu_ticks
    let user = UInt64(t.0), system = UInt64(t.1), idle = UInt64(t.2), nice = UInt64(t.3)
    return (user + system + nice, user + system + idle + nice)
  }
}
