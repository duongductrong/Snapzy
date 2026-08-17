import Foundation
import SnapzyPluginProtocol

/// The message kinds, as the one shared string table. These are the wire
/// names in PROTOCOL.md — never localized, never renamed. Renaming a kind is
/// a protocol major bump.
public enum MessageKind {
  // Host → plugin
  public static let handshake = "handshake"
  public static let activate = "activate"
  public static let invoke = "invoke"
  public static let cancel = "cancel"
  public static let deactivate = "deactivate"
  public static let healthCheck = "healthCheck"

  // Plugin → host
  public static let handshakeAck = "handshakeAck"
  public static let hostCall = "hostCall"
  public static let progress = "progress"
  public static let log = "log"
  public static let result = "result"
  public static let hostCallReply = "hostCallReply"
}
