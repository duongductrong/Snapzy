//
//  main.swift
//  snapzy-dev
//
//  Development-only entry point: `swift run snapzy-dev <command>`. Point it at
//  a Debug build with SNAPZY_APP_PATH=/path/to/Snapzy.app.
//

import SnapzyCLICore

await SnapzyCommand.execute()
