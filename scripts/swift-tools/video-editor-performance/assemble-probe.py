#!/usr/bin/env python3
"""Feed repository camera algorithms and the timing harness to swiftc on stdin.

No generated Swift source is written. The only substitute is the two display-name
localization strings. Metadata storage/migration is outside this CPU experiment.
Production signpost helpers compile with their normal non-Debug no-op behavior.
"""

import hashlib
import json
import pathlib
import sys


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: assemble-probe.py REPO_ROOT")
    root = pathlib.Path(sys.argv[1]).resolve()
    paths = [
        "Snapzy/Features/VideoEditor/Models/VideoEditorAutoFocusSettings.swift",
        "Snapzy/Features/VideoEditor/Models/VideoEditorZoomSegment.swift",
        "Snapzy/Features/VideoEditor/Services/VideoEditorZoomCalculator.swift",
        "Snapzy/Features/VideoEditor/Models/VideoEditorTimelineClip.swift",
        "Snapzy/Features/VideoEditor/Models/VideoEditorSpeedSegment.swift",
        "Snapzy/Features/VideoEditor/Services/VideoEditorTimelineTimeMap.swift",
        "Snapzy/Services/Diagnostics/PerformanceSignpost.swift",
        "Snapzy/Features/VideoEditor/Services/VideoEditorAutoFocusEngine.swift",
    ]
    metadata_path = "Snapzy/Services/Capture/RecordingMetadata.swift"
    metadata = (root / metadata_path).read_text()
    marker = "@MainActor\nenum RecordingMetadataStore"
    if metadata.count(marker) != 1:
        raise SystemExit("RecordingMetadataStore boundary changed; review the probe extraction.")
    chunks = [
        "import SwiftUI\nimport Dispatch\n",
        'nonisolated enum L10n { nonisolated enum VideoEditor { '
        'static let auto = "Auto"; static let manual = "Manual" } }\n',
    ]
    for path in [metadata_path, *paths]:
        text = metadata.split(marker, 1)[0] if path == metadata_path else (root / path).read_text()
        chunks.append(f"#sourceLocation(file: {json.dumps(path)}, line: 1)\n{text}\n#sourceLocation()")
        digest = hashlib.sha256(text.encode()).hexdigest()[:12]
        print(f"source={path} sha256={digest}", file=sys.stderr)
    harness = pathlib.Path(__file__).with_name("camera-cpu-probe.swift")
    chunks.append(f"#sourceLocation(file: {json.dumps(str(harness))}, line: 1)\n{harness.read_text()}\n#sourceLocation()")
    print(
        f"source={metadata_path} extraction=model-prefix; "
        "excluded=metadata-storage-and-migration; shim=two-localization-display-strings",
        file=sys.stderr,
    )
    sys.stdout.write("\n".join(chunks))


if __name__ == "__main__":
    main()
