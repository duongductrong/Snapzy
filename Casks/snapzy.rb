cask "snapzy" do
  version "2.0.0"
  sha256 "d116c97d77490c4dae3fba84ee6ceea4c23962ce4e3672c343467c35ed33c2c1"

  url "https://github.com/duongductrong/Snapzy/releases/download/v#{version}/Snapzy-v#{version}.dmg"
  name "Snapzy"
  desc "Native screenshots, recording, annotation, and editing from the menu bar"
  homepage "https://snapzy.app/"

  auto_updates true
  depends_on macos: :ventura

  app "Snapzy.app"

  # Snapzy's Install button and install.sh link /usr/local/bin/snapzy, which is
  # Homebrew's bin on Intel Macs, so the `binary` link would find it taken.
  # Drop a link there that points into an app's Helpers/snapzy; leave anything else.
  preflight_steps do
    remove "bin/snapzy", base: :homebrew_prefix, symlink_target_contains: ".app/Contents/Helpers/snapzy"
  end

  zap trash: [
    "~/.config/snapzy",
    "~/Library/Application Support/Snapzy",
    "~/Library/HTTPStorages/com.trongduong.snapzy",
    "~/Library/Logs/Snapzy",
    "~/Library/Preferences/com.trongduong.snapzy.plist",
  ]
end
