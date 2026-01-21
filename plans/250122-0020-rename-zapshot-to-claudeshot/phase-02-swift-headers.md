# Phase 02: Swift File Header Updates

**Parent Plan:** [plan.md](./plan.md)
**Dependencies:** [Phase 01](./phase-01-directory-renames.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 260122 |
| Priority | Medium |
| Status | Pending |
| Estimated Effort | 10 minutes |

## Description

Update file header comments in all Swift files from `//  ZapShot` to `//  ClaudeShot`. This is a batch operation affecting ~70 files.

## Key Insights

- All Swift files have consistent header format at line 3
- Pattern: `//  ZapShot` (with two spaces after //)
- Can use sed or find/replace for batch update
- No functional impact, purely cosmetic

## Requirements

1. Update all Swift file headers from ZapShot to ClaudeShot
2. Preserve exact formatting (two spaces after //)

## Related Files

All `.swift` files in `ClaudeShot/` directory (~70 files)

Key directories:
- `ClaudeShot/App/`
- `ClaudeShot/Core/`
- `ClaudeShot/Features/`
- `ClaudeShot/ContentView.swift`

## Implementation Steps

### Step 1: Find all affected files
```bash
cd /Users/duongductrong/Developer/ZapShot
grep -r "//  ZapShot" ClaudeShot --include="*.swift" -l
```

### Step 2: Preview changes
```bash
cd /Users/duongductrong/Developer/ZapShot
grep -r "//  ZapShot" ClaudeShot --include="*.swift" -n | head -20
```

### Step 3: Batch update headers
```bash
cd /Users/duongductrong/Developer/ZapShot
find ClaudeShot -name "*.swift" -exec sed -i '' 's|//  ZapShot|//  ClaudeShot|g' {} \;
```

### Step 4: Verify changes
```bash
cd /Users/duongductrong/Developer/ZapShot
grep -r "//  ZapShot" ClaudeShot --include="*.swift" -l | wc -l
# Should output 0
```

### Step 5: Confirm new headers
```bash
cd /Users/duongductrong/Developer/ZapShot
grep -r "//  ClaudeShot" ClaudeShot --include="*.swift" -l | wc -l
# Should output ~70
```

## Todo List

- [ ] Find all Swift files with ZapShot header
- [ ] Run batch sed replacement
- [ ] Verify no ZapShot headers remain
- [ ] Spot check 3-5 files manually

## Success Criteria

1. Zero Swift files contain `//  ZapShot` in header
2. All Swift files contain `//  ClaudeShot` in header
3. File content otherwise unchanged
4. Project still builds

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Accidental content changes | Low | Medium | Use specific pattern match |
| Missed files | Low | Low | Verify with grep after |
| Encoding issues | Very Low | Low | Use sed -i '' on macOS |

## Rollback Plan

```bash
git checkout -- ClaudeShot/**/*.swift
```
