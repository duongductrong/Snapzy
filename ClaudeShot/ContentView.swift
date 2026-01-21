//
//  ContentView.swift
//  ClaudeShot
//
//  Main window with capture controls
//

import Combine
import SwiftUI

struct ContentView: View {
  @StateObject private var viewModel = ScreenCaptureViewModel()
  
  var body: some View {
    VStack(spacing: 24) {
      // Header
      Text("ClaudeShot")
        .font(.largeTitle)
        .fontWeight(.bold)
      
      Text("Screenshot Tool")
        .font(.subheadline)
        .foregroundColor(.secondary)
      
      Divider()
      
      ScrollView {
        // Permission Status
        permissionSection
        
        Divider()
        
        // Capture Actions
        captureSection
        
        Spacer()
        
        // Status / Result
        statusSection
      }
      
      // Open Preferences
      SettingsLink {
        Text("Open Preferences...")
      }
      .keyboardShortcut(",", modifiers: .command)
    }
    .padding(24)
    .frame(minWidth: 350, minHeight: 350)
  }
  
  // MARK: - Permission Section
  
  private var permissionSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Permissions")
        .font(.headline)
      
      HStack {
        Circle()
          .fill(viewModel.hasPermission ? Color.green : Color.red)
          .frame(width: 12, height: 12)
        
        Text(
          viewModel.hasPermission ? "Screen Recording: Granted" : "Screen Recording: Not Granted"
        )
        .font(.body)
        
        Spacer()
        
        Button("Request Permission") {
          viewModel.requestPermission()
        }
        .disabled(viewModel.hasPermission)
        
        Button("Open Settings") {
          viewModel.openSettings()
        }
      }
    }
  }
  
  // MARK: - Capture Section
  
  private var captureSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Capture Actions")
        .font(.headline)
      
      HStack(spacing: 16) {
        Button {
          viewModel.captureFullscreen()
        } label: {
          VStack {
            Image(systemName: "rectangle.dashed")
              .font(.title)
            Text("Fullscreen")
              .font(.caption)
          }
          .frame(width: 100, height: 60)
        }
        .buttonStyle(.bordered)
        .disabled(!viewModel.hasPermission || viewModel.isCapturing)
        
        Button {
          viewModel.captureArea()
        } label: {
          VStack {
            Image(systemName: "crop")
              .font(.title)
            Text("Area")
              .font(.caption)
          }
          .frame(width: 100, height: 60)
        }
        .buttonStyle(.bordered)
        .disabled(!viewModel.hasPermission || viewModel.isCapturing)
      }
      
      if viewModel.isCapturing {
        HStack {
          ProgressView()
            .scaleEffect(0.8)
          Text("Capturing...")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
  }
  
  // MARK: - Status Section
  
  private var statusSection: some View {
    VStack(spacing: 8) {
      if let lastResult = viewModel.lastCaptureResult {
        switch lastResult {
        case .success(let url):
          HStack {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(.green)
            Text("Saved: \(url.lastPathComponent)")
              .font(.caption)
          }
          
          Button("Show in Finder") {
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
          }
          .font(.caption)
          
        case .failure(let error):
          HStack {
            Image(systemName: "exclamationmark.circle.fill")
              .foregroundColor(.red)
            Text("Error: \(error.localizedDescription)")
              .font(.caption)
          }
        }
      } else {
        Text("Ready to capture")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .padding()
    .background(Color.gray.opacity(0.1))
    .cornerRadius(8)
  }
}

#Preview {
  ContentView()
}
