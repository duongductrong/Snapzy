The key is "onboardingCompleted".

---

Reset Onboarding Commands

Option 1: Delete Only Onboarding Flag (Recommended)

defaults write com.duongductrong.claudeshot onboardingCompleted -bool false

Option 2: Delete All App Preferences

defaults delete com.duongductrong.claudeshot

Option 3: From Xcode Debug Console

Add this temporarily in code and run once:
UserDefaults.standard.removeObject(forKey: "onboardingCompleted")

---

After Resetting

1. Quit ClaudeShot completely (Cmd+Q from menu bar)
2. Run one of the commands above
3. Relaunch ClaudeShot — onboarding window should appear

---

Quick Test Command

# Quit app, reset flag, relaunch

pkill -x ClaudeShot; defaults write com.duongductrong.claudeshot onboardingCompleted -bool false && open /Users/duongductrong/Library/Developer/Xcode/DerivedData/ClaudeShot-*/Build/Products/Debug/ClaudeShot.app


## TODO

- Highlight text content
