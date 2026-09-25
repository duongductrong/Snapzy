# Capture Editing Context

This context describes how captured media moves between Quick Access and an editor while its file ownership remains clear.

## Language

**Capture**:
A screenshot, video, or GIF produced by Snapzy and shown through the capture lifecycle.
_Avoid_: asset, document

**Quick Access card**:
A transient representation of a capture that provides immediate actions such as edit, copy, and save.
_Avoid_: editor session, file browser

**Editing session**:
The in-progress changes for one capture before the user commits or discards them.
_Avoid_: window state, draft file

**Temporary capture**:
A capture kept under Snapzy's temporary ownership until the user chooses its persistent destination.
_Avoid_: unsaved file, cache

**Export destination**:
The persistent user-selected location where a capture is stored after leaving temporary ownership.
_Avoid_: source file, temp path

**Editor commit**:
Applying the current editing session to the capture's current file without changing its ownership or destination.
_Avoid_: export, promote

**Edit recipe**:
The persisted video-editor instructions—ordered clips, trims, zoom, speed, and export context—that can be reopened and changed again.
_Avoid_: rendered output, baked file

**Source snapshot**:
A private copy of the unrendered video source kept so later editor commits can reapply the edit recipe without stacking edits on a rendered file.
_Avoid_: destination, preview

**Promotion**:
Moving a temporary capture into its export destination and ending temporary ownership.
_Avoid_: editor save, commit
