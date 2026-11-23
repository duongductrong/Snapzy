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
//  | record.screen    | RecordScreenParams  | CLIRecordingInfo  |
//  | record.window    | RecordWindowParams  | CLIRecordingInfo  |
//  | record.area      | RecordAreaParams    | CLIRecordingInfo  |
//  | record.stop      | RecordStopParams    | CLIRecordingResult |
//  | record.status    | CLIEmpty            | CLIRecordingStatus |
//  | automation.list  | CLIEmpty            | CLIAutomationList |
//  | automation.run   | CLIAutomationRunParams | CLIAutomationRunResult |
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
  /// Start a recording; `record.stop` ends it and returns the file.
  case recordScreen = "record.screen"
  case recordWindow = "record.window"
  case recordArea = "record.area"
  case recordStop = "record.stop"
  case recordStatus = "record.status"
  /// Protocol 1.1. An app on 1.0 answers `unknownMethod`.
  case automationList = "automation.list"
  /// Waits for the run to finish, including an interactive area selection.
  case automationRun = "automation.run"
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
