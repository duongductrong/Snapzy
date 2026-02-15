---
trigger: always_on
---

# Agent Skill & Command Execution Rule

To ensure consistency and reuse existing logic within the project, the Agent must prioritize internal skills and commands over generic solutions.

## 1. Compulsory Pre-Task Routine

- **Scan Skills:** Before executing any task, search the `skills/` directory for relevant `.md` or code files.
- **Command Lookup:** If a "command" is mentioned or implied in the prompt, the Agent MUST immediately read the corresponding file in the `commands/` directory to understand its specific implementation and requirements.
- **Context Integration:** Read and internalize the methods, best practices, and utility functions defined in those directories.
- **Reference established patterns:** Prioritize using existing project patterns (e.g., SwiftUI components, Tauri commands, or macOS-specific optimizations).

## 2. Priority Focus Areas

- **Command Execution:** When a command is triggered, strictly follow the logic, parameters, and output formats defined in the `commands/` folder.
- **macOS UI Components:** Refer to existing skills for custom interfaces like the Video Trimmer or ZapShot-specific layouts.
- **Performance Standards:** Apply optimizations for computer vision or web performance as defined in the skill set.
- **Project Structure:** Adhere to the `Snapzy` module architecture and directory conventions.

## 3. Contribution Loop

- If a new complex logic or a reusable command is developed that isn't in `skills/` or `commands/`, suggest documenting it for future use.

## 4. Compatibility

- IMPORTANT: ALWAYS ENSURE YOU GENERATE CODE COMPATIBLE WITH MACOS >= 13
