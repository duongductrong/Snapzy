import Foundation

/// Severity of a PluginKit diagnostic.
///
/// Frozen: hosts switch on this to map onto their own logging backend, and four
/// levels are enough. Adding one would silently reroute existing output.
@frozen
public enum PluginLogLevel: Int, Hashable, Sendable, Comparable, CustomStringConvertible {
    case debug = 0
    case info = 1
    case notice = 2
    case error = 3

    public static func < (lhs: PluginLogLevel, rhs: PluginLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .error: return "error"
        }
    }
}

/// Receives PluginKit diagnostics.
///
/// The framework never writes to `stdout` or a system log on its own. Where
/// plugin output goes is a host decision — a document app wants it in its own
/// `OSLog` subsystem, a daemon wants it on stderr, a test wants it in an array.
///
/// `message` is an autoclosure so that formatting a debug string costs nothing
/// when the sink is going to discard it. Plugin activation happens on a launch
/// path; a host with sixty plugins should not pay for log strings it filters.
public protocol PluginLogging: Sendable {
    func log(
        _ level: PluginLogLevel,
        plugin: PluginID?,
        _ message: @autoclosure () -> String
    )
}

/// Discards everything. The default, so an unconfigured host is silent rather
/// than chatty.
public struct SilentPluginLog: PluginLogging {
    public init() {}
    public func log(
        _ level: PluginLogLevel,
        plugin: PluginID?,
        _ message: @autoclosure () -> String
    ) {}
}

/// Forwards messages at or above `minimumLevel` to a supplied sink.
public struct CallbackPluginLog: PluginLogging {
    public let minimumLevel: PluginLogLevel
    private let sink: @Sendable (PluginLogLevel, PluginID?, String) -> Void

    public init(
        minimumLevel: PluginLogLevel = .info,
        sink: @escaping @Sendable (PluginLogLevel, PluginID?, String) -> Void
    ) {
        self.minimumLevel = minimumLevel
        self.sink = sink
    }

    public func log(
        _ level: PluginLogLevel,
        plugin: PluginID?,
        _ message: @autoclosure () -> String
    ) {
        guard level >= minimumLevel else { return }
        sink(level, plugin, message())
    }
}

/// The logging handle a plugin receives.
///
/// A plugin cannot reach the host's raw sink, only this: every message it emits
/// is stamped with its own ``PluginID``. That is not politeness — it is what
/// makes a log line from a shipped app attributable to one plugin, which is the
/// only post-mortem tool available when an in-process plugin takes the host down
/// with it.
public struct PluginLogger: Sendable {
    private let sink: any PluginLogging
    public let plugin: PluginID

    public init(sink: any PluginLogging, plugin: PluginID) {
        self.sink = sink
        self.plugin = plugin
    }

    public func debug(_ message: @autoclosure () -> String) {
        sink.log(.debug, plugin: plugin, message())
    }

    public func info(_ message: @autoclosure () -> String) {
        sink.log(.info, plugin: plugin, message())
    }

    public func notice(_ message: @autoclosure () -> String) {
        sink.log(.notice, plugin: plugin, message())
    }

    public func error(_ message: @autoclosure () -> String) {
        sink.log(.error, plugin: plugin, message())
    }
}
