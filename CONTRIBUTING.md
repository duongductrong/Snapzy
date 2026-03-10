# Contributing to Snapzy

Thanks for contributing to Snapzy.

Snapzy is an open-source native macOS screenshot and screen recording app built with SwiftUI and ScreenCaptureKit. This guide keeps contributions aligned with the current project workflow and structure.

## Ways to contribute

- Report bugs
- Propose features or UX improvements
- Improve documentation
- Submit code fixes or new features
- Help test changes on macOS

## Before you start

- Search existing issues and pull requests before opening a new one.
- For larger changes, open an issue first so the approach can be discussed before implementation.
- Keep contributions focused. Small, reviewable pull requests move faster than broad refactors.

## Development setup

### Requirements

- macOS 14.0+
- Xcode 15.0+
- Command Line Tools: `xcode-select --install`

### Clone and run

```bash
git clone https://github.com/duongductrong/Snapzy.git
cd Snapzy
open Snapzy.xcodeproj
```

Build and run with `Cmd+R`.

### Command-line build

```bash
xcodebuild -project Snapzy.xcodeproj -scheme Snapzy -configuration Debug build
```

For more build details, see [docs/project-build.md](docs/project-build.md).

## Project conventions

Snapzy uses a feature-based structure with limited nesting.

- Keep primary feature entry points at the root of each feature folder.
- Use `Components`, `Managers`, `Services`, and `Models` only when needed.
- Prefer colocating feature-specific logic with the feature.
- Avoid unrelated renames or directory reshuffles in the same pull request.

See [docs/project-structure.md](docs/project-structure.md) for the current architecture guidance.

## Contribution workflow

1. Create a branch from `main`.
2. Make one focused change.
3. Update documentation when behavior, setup, or workflow changes.
4. Validate the change locally.
5. Open a pull request with clear context and test notes.

## Coding guidelines

- Follow the existing Swift and SwiftUI style already used in the repository.
- Prefer clear, descriptive type and file names.
- Keep changes scoped to the problem being solved.
- Add comments only when the intent is not obvious from the code.
- Preserve existing user-facing behavior unless the pull request explicitly changes it.

## Validation

Before opening a pull request, verify the following:

- The project builds successfully in Xcode or via `xcodebuild`
- The affected feature works as expected on macOS
- Permission-sensitive flows are tested when relevant, especially screen recording
- New UI behavior includes screenshots or recordings in the pull request when helpful

If your change affects capture, recording, annotation, export, onboarding, or updates, include manual test steps in the pull request description.

## Pull request checklist

- Describe what changed and why
- Link the related issue when one exists
- Keep the pull request focused and reviewable
- Include screenshots or short recordings for UI changes
- Note any follow-up work or known limitations
- Confirm how you tested the change

## Commit messages

Use short, imperative commit messages. Prefixes such as `feat:`, `fix:`, `docs:`, `refactor:`, and `chore:` are preferred when they fit the change.

Examples:

- `fix: prevent duplicate quick access panels`
- `docs: update local build instructions`
- `chore: clean up release workflow notes`

## Reporting bugs

When filing a bug report, include:

- macOS version
- Snapzy version or commit SHA
- Steps to reproduce
- Expected behavior
- Actual behavior
- Screenshots or screen recordings if relevant

## Security issues

Please do not report security vulnerabilities in public issues. Contact the repository maintainer privately through GitHub first so the issue can be handled responsibly.
