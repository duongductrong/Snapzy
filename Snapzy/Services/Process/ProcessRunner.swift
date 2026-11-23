//
//  ProcessRunner.swift
//  Snapzy
//
//  Runs a child process for automation script / Shortcut steps. The child is
//  spawned in its own process group so a timeout or a cancelled run kills the
//  whole tree (a shell's children too), not just the shell. Output is captured
//  up to a cap; arguments are passed as an argv array, never through a shell
//  command line built by Snapzy.
//

import Darwin
import Foundation

nonisolated struct ProcessRequest: Sendable {
  var executable: URL
  var arguments: [String]
  /// The complete environment of the child (nothing is inherited implicitly).
  var environment: [String: String]
  var currentDirectory: URL?
  var timeout: TimeInterval
  var stdinData: Data?

  init(
    executable: URL,
    arguments: [String] = [],
    environment: [String: String] = [:],
    currentDirectory: URL? = nil,
    timeout: TimeInterval = 30,
    stdinData: Data? = nil
  ) {
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
    self.currentDirectory = currentDirectory
    self.timeout = timeout
    self.stdinData = stdinData
  }
}

nonisolated struct ProcessOutcome: Equatable, Sendable {
  var status: Int32
  var stdout: Data
  var stderr: Data
  var timedOut: Bool
  /// Output beyond `ProcessRunner.outputCap` was dropped.
  var truncated: Bool

  var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
  var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

nonisolated enum ProcessRunnerError: LocalizedError, Equatable {
  case spawnFailed(Int32)

  var errorDescription: String? {
    switch self {
    case .spawnFailed(let code):
      return "Could not start the process (\(String(cString: strerror(code))))"
    }
  }
}

nonisolated enum ProcessRunner {
  /// Bytes kept per stream.
  static let outputCap = 1_048_576
  /// Time between SIGTERM and SIGKILL when stopping a process group.
  static let killGrace: TimeInterval = 1

  /// A minimal environment for children of a GUI app: no user secrets from
  /// Snapzy's own environment, just what tools expect to find.
  static func baseEnvironment(
    from inherited: [String: String] = ProcessInfo.processInfo.environment
  ) -> [String: String] {
    var environment: [String: String] = [
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
      "LANG": inherited["LANG"] ?? "en_US.UTF-8",
    ]
    for key in ["HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LC_ALL", "LC_CTYPE"] {
      if let value = inherited[key] { environment[key] = value }
    }
    return environment
  }

  /// Runs the request to completion, timeout or task cancellation (both kill the
  /// process group). Throws only when the process cannot be started.
  static func run(_ request: ProcessRequest) async throws -> ProcessOutcome {
    let stdout = OutputBuffer(cap: outputCap)
    let stderr = OutputBuffer(cap: outputCap)
    let outPipe = Pipe()
    let errPipe = Pipe()
    let inPipe = Pipe()

    let pid = try spawn(request, stdin: inPipe, stdout: outPipe, stderr: errPipe)
    // Parent keeps only its ends.
    try? outPipe.fileHandleForWriting.close()
    try? errPipe.fileHandleForWriting.close()
    try? inPipe.fileHandleForReading.close()

    // Read both streams to EOF on background threads, keeping at most `outputCap`.
    let outReader = startReading(outPipe.fileHandleForReading, into: stdout)
    let errReader = startReading(errPipe.fileHandleForReading, into: stderr)

    // Feed stdin off the caller's thread; a child that never reads must not block us.
    let stdinData = request.stdinData
    let writer = inPipe.fileHandleForWriting
    DispatchQueue.global(qos: .utility).async {
      if let stdinData, !stdinData.isEmpty {
        signal(SIGPIPE, SIG_IGN)
        try? writer.write(contentsOf: stdinData)
      }
      try? writer.close()
    }

    let state = RunState()
    let timeoutTask = Task.detached {
      try? await Task.sleep(nanoseconds: UInt64(max(request.timeout, 0.1) * 1_000_000_000))
      guard !Task.isCancelled else { return }
      state.markTimedOut()
      terminateGroup(pid)
    }

    let status: Int32 = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
          var raw: Int32 = 0
          while waitpid(pid, &raw, 0) == -1, errno == EINTR {}
          continuation.resume(returning: raw)
        }
      }
    } onCancel: {
      terminateGroup(pid)
    }
    timeoutTask.cancel()
    // Children that outlived the leader (backgrounded jobs) go too.
    kill(-pid, SIGKILL)

    // EOF once every writer (the shell and anything it started) is gone.
    await outReader.value
    await errReader.value

    return ProcessOutcome(
      status: exitCode(status),
      stdout: stdout.data,
      stderr: stderr.data,
      timedOut: state.timedOut,
      truncated: stdout.truncated || stderr.truncated
    )
  }

  // MARK: - Private

  private static func spawn(_ request: ProcessRequest, stdin: Pipe, stdout: Pipe, stderr: Pipe) throws -> pid_t {
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_adddup2(&actions, stdin.fileHandleForReading.fileDescriptor, STDIN_FILENO)
    posix_spawn_file_actions_adddup2(&actions, stdout.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
    posix_spawn_file_actions_adddup2(&actions, stderr.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
    if let directory = request.currentDirectory {
      posix_spawn_file_actions_addchdir_np(&actions, directory.path)
    }

    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    // Own process group (pgid = pid) so the whole tree can be signalled; close
    // every other inherited descriptor.
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
    posix_spawnattr_setpgroup(&attributes, 0)
    var defaultSignals = sigset_t()
    sigfillset(&defaultSignals)
    posix_spawnattr_setsigdefault(&attributes, &defaultSignals)
    var noMask = sigset_t()
    sigemptyset(&noMask)
    posix_spawnattr_setsigmask(&attributes, &noMask)

    let argv = [request.executable.path] + request.arguments
    let envp = request.environment.map { "\($0.key)=\($0.value)" }
    var pid: pid_t = 0
    let result = withCStrings(argv) { argvPointer in
      withCStrings(envp) { envPointer in
        posix_spawn(&pid, request.executable.path, &actions, &attributes, argvPointer, envPointer)
      }
    }
    guard result == 0 else { throw ProcessRunnerError.spawnFailed(result) }
    return pid
  }

  private static func withCStrings<R>(_ strings: [String], _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) -> R) -> R {
    var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
    pointers.append(nil)
    defer { pointers.forEach { free($0) } }
    return pointers.withUnsafeBufferPointer { body($0.baseAddress!) }
  }

  private static func terminateGroup(_ pid: pid_t) {
    kill(-pid, SIGTERM)
    DispatchQueue.global().asyncAfter(deadline: .now() + killGrace) {
      kill(-pid, SIGKILL)
    }
  }

  private static func startReading(_ handle: FileHandle, into buffer: OutputBuffer) -> Task<Void, Never> {
    Task.detached(priority: .utility) {
      while true {
        guard let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
        buffer.append(chunk)
      }
      try? handle.close()
    }
  }

  private static func exitCode(_ status: Int32) -> Int32 {
    let signal = status & 0x7F
    if signal == 0 { return (status >> 8) & 0xFF }
    return 128 + signal
  }

  private final class OutputBuffer: @unchecked Sendable {
    private let cap: Int
    private let lock = NSLock()
    private var storage = Data()
    private var didTruncate = false

    init(cap: Int) {
      self.cap = cap
    }

    func append(_ chunk: Data) {
      guard !chunk.isEmpty else { return }
      lock.withLock {
        let room = cap - storage.count
        if room <= 0 {
          didTruncate = true
        } else if chunk.count > room {
          storage.append(chunk.prefix(room))
          didTruncate = true
        } else {
          storage.append(chunk)
        }
      }
    }

    var data: Data { lock.withLock { storage } }
    var truncated: Bool { lock.withLock { didTruncate } }
  }

  private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private var didTimeOut = false

    func markTimedOut() { lock.withLock { didTimeOut = true } }
    var timedOut: Bool { lock.withLock { didTimeOut } }
  }
}
