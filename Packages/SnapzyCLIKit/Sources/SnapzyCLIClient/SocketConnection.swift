//
//  SocketConnection.swift
//  SnapzyCLIClient
//
//  Blocking AF_UNIX stream connection that sends and receives whole frames.
//  The CLI makes one request at a time, so blocking I/O with poll(2) timeouts
//  is simpler and more predictable than an event loop.
//

import Darwin
import Foundation
import SnapzyCLIProtocol

public enum SocketConnectionError: Error, Equatable {
  /// No socket file: the app is not running or the CLI server is off.
  case socketMissing
  /// A stale socket file with no listener.
  case connectionRefused
  case pathTooLong
  case timedOut
  case closedByPeer
  case frame(FrameError)
  case system(operation: String, errno: Int32)

  /// The app may come up if launched (missing or stale socket).
  public var suggestsAppNotListening: Bool {
    self == .socketMissing || self == .connectionRefused
  }
}

public final class SocketConnection {
  private var fileDescriptor: Int32
  private var decoder = FrameDecoder()

  public static func connect(path: String) throws -> SocketConnection {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8)
    guard pathBytes.count <= SocketLocation.maxPathByteCount else {
      throw SocketConnectionError.pathTooLong
    }
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
      buffer.copyBytes(from: pathBytes)
      buffer[pathBytes.count] = 0
    }
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
      throw SocketConnectionError.system(operation: "socket", errno: errno)
    }

    var noSigPipe: Int32 = 1
    setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

    let result = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard result == 0 else {
      let connectErrno = errno
      Darwin.close(descriptor)
      switch connectErrno {
      case ENOENT: throw SocketConnectionError.socketMissing
      case ECONNREFUSED: throw SocketConnectionError.connectionRefused
      default: throw SocketConnectionError.system(operation: "connect", errno: connectErrno)
      }
    }

    // Non-blocking so a peer that stops reading cannot stall `write` past the
    // poll(2) deadline; send/receive already retry on EAGAIN.
    let flags = fcntl(descriptor, F_GETFL)
    guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
      let fcntlErrno = errno
      Darwin.close(descriptor)
      throw SocketConnectionError.system(operation: "fcntl", errno: fcntlErrno)
    }

    return SocketConnection(fileDescriptor: descriptor)
  }

  private init(fileDescriptor: Int32) {
    self.fileDescriptor = fileDescriptor
  }

  deinit {
    close()
  }

  public func close() {
    guard fileDescriptor >= 0 else { return }
    Darwin.close(fileDescriptor)
    fileDescriptor = -1
  }

  public func send(_ payload: Data, timeout: TimeInterval) throws {
    let frame: Data
    do {
      frame = try Frame.encode(payload)
    } catch let error as FrameError {
      throw SocketConnectionError.frame(error)
    }

    let deadline = Date().addingTimeInterval(timeout)
    var offset = 0
    while offset < frame.count {
      try waitUntilReady(events: Int16(POLLOUT), deadline: deadline)
      let written = frame.withUnsafeBytes { buffer in
        Darwin.write(fileDescriptor, buffer.baseAddress! + offset, frame.count - offset)
      }
      if written < 0 {
        if errno == EINTR || errno == EAGAIN { continue }
        if errno == EPIPE || errno == ECONNRESET { throw SocketConnectionError.closedByPeer }
        throw SocketConnectionError.system(operation: "write", errno: errno)
      }
      offset += written
    }
  }

  public func receive(timeout: TimeInterval) throws -> Data {
    let deadline = Date().addingTimeInterval(timeout)
    var chunk = [UInt8](repeating: 0, count: 64 * 1024)

    while true {
      do {
        if let payload = try decoder.nextPayload() {
          return payload
        }
      } catch let error as FrameError {
        throw SocketConnectionError.frame(error)
      }

      try waitUntilReady(events: Int16(POLLIN), deadline: deadline)
      let count = Darwin.read(fileDescriptor, &chunk, chunk.count)
      if count < 0 {
        if errno == EINTR || errno == EAGAIN { continue }
        throw SocketConnectionError.system(operation: "read", errno: errno)
      }
      if count == 0 {
        throw SocketConnectionError.closedByPeer
      }
      decoder.append(Data(chunk[0 ..< count]))
    }
  }

  private func waitUntilReady(events: Int16, deadline: Date) throws {
    guard fileDescriptor >= 0 else { throw SocketConnectionError.closedByPeer }

    while true {
      let remaining = deadline.timeIntervalSinceNow
      guard remaining > 0 else { throw SocketConnectionError.timedOut }

      var descriptor = pollfd(fd: fileDescriptor, events: events, revents: 0)
      let milliseconds = Int32(min(remaining * 1000, Double(Int32.max)).rounded(.up))
      let ready = poll(&descriptor, 1, milliseconds)
      if ready > 0 { return }
      if ready == 0 { throw SocketConnectionError.timedOut }
      if errno == EINTR { continue }
      throw SocketConnectionError.system(operation: "poll", errno: errno)
    }
  }
}
