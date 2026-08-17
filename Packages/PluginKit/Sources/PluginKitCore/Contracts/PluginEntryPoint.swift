import Foundation

/// How a host finds the ``Plugin`` type inside a compiled plugin.
///
/// Separate from ``Plugin`` itself so that `Plugin` stays a pure behavioural
/// protocol with no static requirements — a plugin can then be an actor, a class,
/// or a generic wrapper, and the *bootstrap* concern lives here instead of
/// polluting the type that has to sit on a binary boundary forever.
public protocol PluginEntryPoint {
    /// Constructs the plugin. Called once per activation cycle.
    static func makePlugin() -> any Plugin

    /// Host vocabularies this build was compiled against.
    ///
    /// The host reads this **before** calling ``makePlugin()`` and refuses to go
    /// further on a mismatch. That ordering matters: a plugin linked against an
    /// incompatible contract can fail in ways that are indistinguishable from
    /// memory corruption once its code is running, so the handshake has to
    /// happen while backing out is still clean.
    ///
    /// Defaults to empty, which means "trust the manifest". Override when the
    /// plugin links a contract package, so the *binary's* view and the manifest's
    /// view can be cross-checked rather than assumed equal.
    static var declaredContracts: [ContractDependency] { get }
}

extension PluginEntryPoint {
    public static var declaredContracts: [ContractDependency] { [] }
}
