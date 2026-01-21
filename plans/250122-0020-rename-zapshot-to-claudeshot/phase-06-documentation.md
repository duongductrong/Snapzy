# Phase 06: Documentation Updates

**Parent Plan:** [plan.md](./plan.md)
**Dependencies:** [Phase 01](./phase-01-directory-renames.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 260122 |
| Priority | Medium |
| Status | Pending |
| Estimated Effort | 15 minutes |

## Description

Update documentation files to reflect the rename from ZapShot to ClaudeShot. This includes README, release workflow, appcast, and testing docs.

## Key Insights

- 4 documentation files need updates
- README.md is most user-facing
- appcast.xml affects auto-update functionality
- Historical plan files in `plans/` should NOT be updated

## Requirements

1. Update README.md with new app name
2. Update RELEASE_WORKFLOW.md references
3. Update appcast.xml title and URLs
4. Update TESTING.md app references
5. Do NOT update historical plan files

## Related Files

| File | Path | Changes Needed |
|------|------|----------------|
| README.md | `/Users/duongductrong/Developer/ZapShot/README.md` | App name, project file reference |
| RELEASE_WORKFLOW.md | `/Users/duongductrong/Developer/ZapShot/RELEASE_WORKFLOW.md` | Multiple references |
| appcast.xml | `/Users/duongductrong/Developer/ZapShot/appcast.xml` | Title, download URLs |
| TESTING.md | `/Users/duongductrong/Developer/ZapShot/TESTING.md` | App references |

## Implementation Steps

### Step 1: README.md

Update the following:
```markdown
# ZapShot → # ClaudeShot

"A modern macOS screenshot application..." (keep description)

Open `ZapShot.xcodeproj` → Open `ClaudeShot.xcodeproj`

ZapShot requires Screen Recording → ClaudeShot requires Screen Recording
```

### Step 2: RELEASE_WORKFLOW.md

Search and replace all ZapShot references:
```bash
cd /Users/duongductrong/Developer/ZapShot
grep -n "ZapShot" RELEASE_WORKFLOW.md
```

Update each occurrence to ClaudeShot.

### Step 3: appcast.xml

Update:
- `<title>` element
- Download URLs (if hosting changes)
- Any ZapShot references in descriptions

```bash
cd /Users/duongductrong/Developer/ZapShot
grep -n "ZapShot" appcast.xml
```

### Step 4: TESTING.md

```bash
cd /Users/duongductrong/Developer/ZapShot
grep -n "ZapShot" TESTING.md
```

Update app name references.

### Step 5: Verify all docs updated
```bash
cd /Users/duongductrong/Developer/ZapShot
grep -l "ZapShot" *.md appcast.xml 2>/dev/null
# Should return empty (no matches)
```

## Todo List

- [ ] Update README.md (title, project file, app name)
- [ ] Update RELEASE_WORKFLOW.md
- [ ] Update appcast.xml
- [ ] Update TESTING.md
- [ ] Verify no ZapShot references in root docs
- [ ] Skip historical plan files (intentional)

## Success Criteria

1. README.md shows ClaudeShot as app name
2. Build instructions reference ClaudeShot.xcodeproj
3. appcast.xml has correct app title
4. No ZapShot references in root documentation files

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Broken download URLs | Medium | High | Verify URLs after hosting changes |
| Missed documentation | Low | Low | Search after changes |
| Sparkle update issues | Medium | Medium | Test auto-update after release |

## Unresolved Questions

1. Will the download hosting change URLs?
   - If yes: Update appcast.xml download links
   - If no: Keep existing URLs

2. Will GitHub repository be renamed?
   - If yes: Update any repo URLs
   - If no: Keep existing repo URLs

## Files to NOT Update

- `plans/**/*` - Historical documentation, should preserve original context
- `.claude/**/*` - Claude configuration, no ZapShot references

## Rollback Plan

```bash
git checkout -- README.md RELEASE_WORKFLOW.md appcast.xml TESTING.md
```
