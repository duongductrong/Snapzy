//
//  AnnotateAgentCLIProcess.swift
//  Snapzy
//
//  Runs an agent CLI in its own process group so Stop can end it and every
//  child it started (MCP servers, node workers): SIGTERM, then SIGKILL after a
//  grace period. stdout is read line by line; the tail of stderr is kept for
//  error messages. stdin is /dev/null (OpenCode waits on an open stdin).
//

import Darwin
import Foundation

nonisolated final class AnnotateAgentCLIProcess: @unchecked Sendable {
  struct Exit: Equatable {
    let status: Int32
    /// Last bytes of stderr, for "not logged in", "quota exceeded"….
    let stderrTail: String
  }

  enum LaunchError: Error, Equatable {
    case spawnFailed(Int32)
  }

  static let stderrTailBytes = 4096
  static let terminateGracePeriod: TimeInterval = 2

  let pid: pid_t
  private let stdoutHandle: FileHandle
  private let stderrHandle: FileHandle
  private let lock = NSLock()
  private var stderrBuffer = Data()
  private var isTerminated = false
  private let stderrClosed = DispatchSemaphore(value: 0)

  /// Starts `executable` with `arguments` in `directory`. The environment replaces the app's.
  /// `stdinPath` feeds a file to stdin (prompts too long or too private for argv); default /dev/null.
  init(
    executable: String,
    arguments: [String],
    environment: [String: String],
    directory: String,
    stdinPath: String? = nil
  ) throws {
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()

    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, stdinPath ?? "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_adddup2(&actions, stdoutPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
    posix_spawn_file_actions_adddup2(&actions, stderrPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
    posix_spawn_file_actions_addchdir_np(&actions, directory)

    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    // Own process group (pgid = pid), so Stop reaches grandchildren too.
    posix_spawnattr_setpgroup(&attributes, 0)
    // Close every descriptor the app holds (sockets, files) in the child.
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))

    let argv = ([executable] + arguments).map { strdup($0) } + [nil]
    let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer {
      argv.forEach { free($0) }
      envp.forEach { free($0) }
    }

    var pid: pid_t = 0
    let result = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
    try? stdoutPipe.fileHandleForWriting.close()
    try? stderrPipe.fileHandleForWriting.close()
    guard result == 0 else {
      throw LaunchError.spawnFailed(result)
    }
    self.pid = pid
    stdoutHandle = stdoutPipe.fileHandleForReading
    stderrHandle = stderrPipe.fileHandleForReading
    readStderr()
  }

  deinit {
    terminate()
  }

  /// stdout split into lines (without the newline). Ends at EOF.
  var lines: AsyncStream<String> {
    let handle = stdoutHandle
    return AsyncStream { continuation in
      let thread = Thread {
        var pending = Data()
        while true {
          let chunk = handle.availableData
          if chunk.isEmpty { break }
          pending.append(chunk)
          while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex ..< newline]
            continuation.yield(String(decoding: line, as: UTF8.self))
            pending.removeSubrange(pending.startIndex ... newline)
          }
        }
        if !pending.isEmpty {
          continuation.yield(String(decoding: pending, as: UTF8.self))
        }
        continuation.finish()
      }
      thread.name = "Snapzy agent CLI stdout"
      thread.start()
    }
  }

  /// Waits for the process to exit (off the main thread). Call once.
  func waitForExit() async -> Exit {
    let pid = pid
    let status: Int32 = await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0, errno == EINTR {}
        continuation.resume(returning: status)
      }
    }
    // The stderr handler runs asynchronously: let it drain ("not logged in" is often the last line).
    let closed = stderrClosed
    _ = await Task.detached { closed.wait(timeout: .now() + 0.5) }.value
    // Not marked terminated: children it left behind (MCP servers) still get `terminate()`.
    let tail = stderrTail()
    let exitStatus = (status & 0x7F) == 0 ? (status >> 8) & 0xFF : 128 + (status & 0x7F)
    return Exit(status: exitStatus, stderrTail: tail)
  }

  /// SIGTERM to the whole group, SIGKILL after the grace period if it is still there.
  func terminate() {
    lock.lock()
    let alreadyGone = isTerminated
    isTerminated = true
    lock.unlock()
    guard !alreadyGone else { return }
    let group = pid
    kill(-group, SIGTERM)
    DispatchQueue.global().asyncAfter(deadline: .now() + Self.terminateGracePeriod) {
      // ESRCH when the group already exited; harmless.
      kill(-group, SIGKILL)
    }
  }

  var stderrTailForTesting: String { stderrTail() }

  private func stderrTail() -> String {
    lock.withLock { String(decoding: stderrBuffer, as: UTF8.self) }
  }

  private func readStderr() {
    stderrHandle.readabilityHandler = { [weak self] handle in
      let chunk = handle.availableData
      guard let self else { return }
      if chunk.isEmpty {
        handle.readabilityHandler = nil
        self.stderrClosed.signal()
        return
      }
      self.lock.lock()
      self.stderrBuffer.append(chunk)
      if self.stderrBuffer.count > Self.stderrTailBytes {
        self.stderrBuffer.removeFirst(self.stderrBuffer.count - Self.stderrTailBytes)
      }
      self.lock.unlock()
    }
  }
}
