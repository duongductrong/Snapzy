//
//  CLIMethod.swift
//  SnapzyCLIProtocol
//
//  Every method the app serves, with its params and result types.
//
//  | Method           | Params              | Result            |
//  | ---------------- | ------------------- | ----------------- |
//  | hello            | HelloRequest        | HelloResponse     |
//  | system.status    | CLIEmpty            | CLIStatus         |
//  | list.displays    | CLIEmpty            | CLIDisplayList    |
//  | list.windows     | ListWindowsParams   | CLIWindowList     |
//  | list.apps        | CLIEmpty            | CLIAppList        |
//  | capture.screen   | CaptureScreenParams | CLICaptureResult  |
//  | capture.window   | CaptureWindowParams | CLICaptureResult  |
//  | capture.area     | CaptureAreaParams   | CLICaptureResult  |
//  | agent.tools      | AgentToolsParams    | AgentToolList     |
//  | agent.call       | AgentCallParams     | AgentCallResult   |
//

import Foundation

public enum CLIMethod: String, Codable, Sendable, CaseIterable {
  case hello
  case systemStatus = "system.status"
  case listDisplays = "list.displays"
  case listWindows = "list.windows"
  case listApps = "list.apps"
  case captureScreen = "capture.screen"
  case captureWindow = "capture.window"
  case captureArea = "capture.area"
  /// Annotate AI tools for `snapzy mcp`; authorized by a session token (CLIAgentModels).
  case agentTools = "agent.tools"
  case agentCall = "agent.call"
}

public struct ListWindowsParams: Codable, Sendable, Equatable {
  /// Localized app name or bundle ID; `nil` lists every app.
  public let app: String?

  /// Include windows that are not on screen (minimized, other Spaces).
  public let includeOffscreen: Bool

  public init(app: String? = nil, includeOffscreen: Bool = false) {
    self.app = app
    self.includeOffscreen = includeOffscreen
  }
}
