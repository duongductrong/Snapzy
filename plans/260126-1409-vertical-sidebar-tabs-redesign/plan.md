# Vertical Sidebar Tabs Redesign Plan

## Overview
Convert VideoEditor right sidebar from horizontal segmented tabs to vertical tab bar on right edge. New layout: `[Content Area] | [Vertical Tab Bar]`

## Current State
- Horizontal `SegmentedTabButton` in `HStack` at sidebar header
- Two tabs: Background, Zoom
- Fixed 320px sidebar width
- Auto-switch to Zoom when `selectedZoomId` changes

## Target State
- Vertical tab bar (60-80px width) on RIGHT side of sidebar
- Icon + text stacked vertically per tab item
- Content area fills remaining space
- Maintain all existing functionality

## Phases

| Phase | Description | Status | Progress |
|-------|-------------|--------|----------|
| 01 | Vertical Tab Bar Implementation | Pending | 0% |

## Phase Files
- [Phase 01: Vertical Tab Bar Implementation](./phase-01-vertical-tab-bar-implementation.md)

## Key Decisions
1. Create reusable `VerticalTabBar` and `VerticalTabItem` components
2. Keep existing `VideoEditorSidebarTab` enum unchanged
3. Layout via `HStack`: content + divider + vertical tabs
4. Tab width: 64px (balanced icon/text fit)

## Success Criteria
- Vertical tabs render correctly on right edge
- Tab switching works with animation
- Auto-switch to Zoom preserved
- Hover/selected states visible
- No regression in existing functionality

## Reports
- [01-codebase-analysis.md](./reports/01-codebase-analysis.md)
