cask "snapzy" do
  version "2.0.0"
  sha256 "d116c97d77490c4dae3fba84ee6ceea4c23962ce4e3672c343467c35ed33c2c1"

  url "https://github.com/duongductrong/Snapzy/releases/download/v#{version}/Snapzy-v#{version}.dmg"
  name "Snapzy"
  desc "Native macOS screenshots, recording, annotation, and editing from the menu bar"
  homepage "https://github.com/duongductrong/Snapzy"

  depends_on macos: :ventura

  app "Snapzy.app"

  zap trash: [
    "~/Library/Application Support/Snapzy",
    "~/Library/Preferences/Snapzy.plist",
    "~/Library/Caches/Snapzy",
  ]

  # NOTE (pre-notarization): Snapzy was previously unsigned — kept for reference.
  # Uncomment if a future build ships without Developer ID notarization.
  # caveats <<~EOS
  #   Snapzy is not signed with an Apple Developer ID certificate.
  #   On first launch, macOS may block the app. To open it:
  #     Right-click Snapzy.app → Open → Open
  #   Or run:
  #     xattr -cr /Applications/Snapzy.app
  # EOS

  caveats <<~EOS
    Snapzy is signed and notarized by Apple (Developer ID).
    On first launch, grant Screen Recording permission when prompted in System Settings.
  EOS
end
