//
//  ZapShotApp.swift
//  ZapShot
//
//  Main app entry point
//

import SwiftUI

@main
struct ZapShotApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
