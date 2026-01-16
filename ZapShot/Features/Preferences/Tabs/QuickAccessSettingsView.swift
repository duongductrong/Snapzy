//
//  QuickAccessSettingsView.swift
//  ZapShot
//
//  Quick Access (floating overlay) settings tab
//

import SwiftUI

struct QuickAccessSettingsView: View {
  @ObservedObject private var manager = FloatingScreenshotManager.shared
  
  @State private var positionIsLeft: Bool = false
  
  var body: some View {
    Form {
      Section("Position") {
        Picker("Screen edge", selection: $positionIsLeft) {
          Text("Left").tag(true)
          Text("Right").tag(false)
        }
        .pickerStyle(.segmented)
        .onChange(of: positionIsLeft) { _, newValue in
          manager.setPosition(newValue ? .bottomLeft : .bottomRight)
        }
      }
      
      Section("Appearance") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Overlay Size")
          HStack {
            Text("Small")
              .font(.caption)
              .foregroundColor(.secondary)
            Slider(value: $manager.overlayScale, in: 0.75...1.5, step: 0.25)
            Text("Large")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }
      
      Section("Behaviors") {
        
        VStack(alignment: .leading, spacing: 12) {
          Toggle("Enable floating overlay", isOn: $manager.isEnabled)
          
          Divider()
          
          Toggle("Auto-close overlay", isOn: $manager.autoDismissEnabled)
          
          if manager.autoDismissEnabled {
            HStack {
              Text("Close after")
              Slider(value: $manager.autoDismissDelay, in: 3...30, step: 1)
                .frame(width: 150)
              Text("\(Int(manager.autoDismissDelay))s")
                .frame(width: 35)
                .monospacedDigit()
            }
            .padding(.leading, 20)
          }
          
          Divider()
          
          Toggle("Enable drag & drop to apps", isOn: $manager.dragDropEnabled)
          
          Toggle("Show cloud upload button", isOn: $manager.showCloudUpload)
        }
        .padding(4)
        
      }
    }
    .formStyle(.grouped)
    .onAppear {
      positionIsLeft = manager.position.isLeftSide
    }
  }
}

#Preview {
  QuickAccessSettingsView()
    .frame(width: 500, height: 400)
}
