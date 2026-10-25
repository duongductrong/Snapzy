//
//  main.swift
//  snapzy
//
//  The `snapzy` command line tool, embedded at Snapzy.app/Contents/Helpers.
//  All commands live in Packages/SnapzyCLIKit (SnapzyCLICore).
//

import SnapzyCLICore

await SnapzyCommand.execute()
