---
description: ⚡⚡⚡ Use subagents to plan and fix hard issues
argument-hint: [issues]
---

**Ultrathink** to plan & start fixing these issues follow the Orchestration Protocol, Core Responsibilities, Subagents Team and Development Rules:
<issues>$ARGUMENTS</issues>

## Workflow:

If the user provides a screenshots or videos, use `ai-multimodal` skill to describe as detailed as possible the issue, make sure developers can predict the root causes easily based on the description.

Use `sequential-thinking` skill to break complex problems into sequential thought steps.
Use `problem-solving` skills to tackle the issues.
Analyze the skills catalog and activate other skills that are needed for the task during the process.

1. Use `debugger` subagent to find the root cause of the issues and report back to main agent.
2. Use `researcher` subagent to research quickly about the root causes on the internet (if needed) and report back to main agent.
3. Use `planner` subagent to create an implementation plan based on the reports, then report back to main agent.
4. Then use general agent (main agent) to implement the plan step by step.
5. Use `tester` subagent to write test cases and run the tests, make sure it works, then report back to main agent.
6. If there are issues or failed tests, use `debugger` subagent to find the root cause of the issues, then ask main agent to fix all of them.
7. Repeat the process until all tests pass or no more issues are reported.
8. After finishing, delegate to `code-reviewer` subagent to review code.
   If there are critical issues, ask main agent to improve the code and test everything again.
   Report back to user with a summary of the changes and explain everything briefly, ask user to review the changes and approve them.
9. Project Management & Documentation:
   **If user approves the changes:** Use `project-manager` and `docs-manager` subagents in parallel to update the project progress and documentation:
   - Use `project-manager` subagent to update the project progress and task status in the given plan file.
   - Use `docs-manager` subagent to update the docs in `./docs` directory if needed.
   - Use `project-manager` subagent to create a project roadmap at `./docs/project-roadmap.md` file.
   - **IMPORTANT:** Sacrifice grammar for the sake of concision when writing outputs.
     **If user rejects the changes:** Ask user to explain the issues and ask main agent to fix all of them and repeat the process.
10. Final Report:

- Report back to user with a summary of the changes and explain everything briefly, guide user to get started and suggest the next steps.
- Ask the user if they want to commit and push to git repository, if yes, use `git-manager` subagent to commit and push to git repository.

* **IMPORTANT:** Sacrifice grammar for the sake of concision when writing reports.
* **IMPORTANT:** In reports, list any unresolved questions at the end, if any.

**REMEMBER**:

- You can always generate images with `ai-multimodal` skills on the fly for visual assets.
- You always read and analyze the generated assets with `ai-multimodal` skills to verify they meet requirements.
- For image editing (removing background, adjusting, cropping), use `ImageMagick` skill or similar tools as needed.
