# Annotate Feature Implementation Plan

**Date:** 2026-01-15
**Feature:** Screenshot Annotation Window
**Complexity:** High

## Overview

Implement a full-featured annotation window for ZapShot that opens when user double-taps a floating screenshot item. The window provides comprehensive image editing tools similar to CleanShot X or Shottr.

## Plan Structure

- `overview.md` - This file (summary + unresolved questions)
- `architecture.md` - File structure and dependencies
- `phases.md` - Implementation phases and order
- `file-details.md` - Detailed file specifications
- `keyboard-shortcuts.md` - Keyboard shortcut mappings

## Summary

| Metric | Value |
|--------|-------|
| Total Files | ~30 |
| New Directories | 8 |
| Modified Files | 2 |
| Phases | 8 |

## Unresolved Questions

1. **Cloud Upload:** What service should be used? Placeholder for now? answer: Placeholder for now
2. **Screen Recording Icon:** Is this for future video recording feature? Include as placeholder? answer: Place holder for now
3. **Custom Wallpapers:** Where to store user-added wallpapers? App sandbox or user-selected folder? answer: user-selected folder
4. **Blurred Backgrounds:** Pre-generate blurred versions of wallpapers or blur on-the-fly?
5. **Multiple Windows:** Allow multiple annotation windows simultaneously or single instance? answer: multiple annotation windows simultaneously
