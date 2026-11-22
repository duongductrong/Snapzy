# Cloud Uploads

Bring-your-own-storage cloud uploads for captures: AWS S3, Cloudflare R2, Google Drive, and the imgbb image host. No Snapzy servers, no telemetry — files go straight from the Mac to the user's bucket, drive, or imgbb account.

Verified against `Snapzy/Services/Cloud/`, `Snapzy/Features/Preferences/Components/PreferencesCloud*.swift`, and upload call sites at HEAD (`v2.3.0-beta.9`).

## Current state (as of `dd4ccd5`)

- The after-capture **auto-upload** preference (`AfterCaptureAction.uploadToCloud`) was removed at `dd4ccd5`.
- Uploads are **manual-only**, from:
  - **Quick Access card** — `.uploadToCloud` action, default `bottomTrailing` slot (`QuickAccessActionKind.defaultAssignments`).
  - **Annotate** — bottom-bar button + ⌘U (`AnnotateShortcutManager.defaultCloudUpload`); re-upload on save/copy uploads the new render, then deletes the old cloud object in the background (`AnnotateWindowController`, `oldCloudKey` cleanup).
  - **Video Editor** — bottom-bar button (label flips to "Re-upload" once a `cloudKey` exists; overwrite path) + post-export upload offer via `.videoEditorCloudUpload` notification (`VideoEditorWindowController` guards).
  - **History** — context menu (`HistoryContextMenu`, gated on `CloudManager.shared.isConfigured`).
- Editor/card entry points are gated on `CloudManager.shared.isConfigured` **and** `QuickAccessActionConfigurationStore.shared.isEnabled(.uploadToCloud)` (Quick Access action customization can hide the action).

## Provider architecture

```mermaid
flowchart LR
    UI["Quick Access / Annotate /<br/>Video Editor / History"] --> CM["CloudManager<br/>(facade, MainActor)"]
    CM --> KS["CloudKeychainStore<br/>(secrets)"]
    CM --> P{"CloudProvider protocol"}
    P --> S3["S3CloudProvider"]
    P --> R2["R2CloudProvider"]
    P --> GD["GoogleDriveCloudProvider"]
    P --> IB["ImgbbCloudProvider"]
    S3 --> SIG["AWSV4Signer (SigV4)"]
    S3 --> MP["S3MultipartUploader<br/>>50 MB, 10 MB parts"]
    R2 --> S3
    GD --> OA["GoogleDriveOAuthService<br/>(NWListener loopback)"]
    CM --> DB["CloudUploadHistoryStore<br/>(GRDB snapzy.db)"]
    CM --> TH["thumbnails/<br/>200px JPEG"]
```

- `CloudProvider` protocol (`CloudProvider.swift`): `upload(fileURL:contentType:expireTime:existingKey:progress:)`, `generatePublicURL(for:)`, `delete(key:)`, `setExpiration(days:)`, `removeExpiration()`, `validate()`.
- `S3CloudProvider`: pure-Foundation SigV4 signing (`AWSV4Signer`), path-style URLs, multipart above 50 MB (`S3MultipartUploader.multipartThreshold`, 10 MB parts), optional custom domain for public URLs. Objects live under the `snapzy/` prefix, named by the share link style (`CloudShareLinkStyle`): `snapzy/<timestamp>-<8 hex>-<name>.<ext>` for `descriptive` (default), `snapzy/<12 random base62 characters>.<ext>` for `short`. Names and extensions are reduced to URL-safe ASCII, and a long name is cut so the key stays within the 1,024 bytes S3 and R2 accept. Lifecycle rule ID `snapzy-auto-expire`.
- `R2CloudProvider`: thin wrapper over S3 with `region = "auto"` and the account endpoint.
- `GoogleDriveCloudProvider`: OAuth desktop flow via `GoogleDriveOAuthService` (NWListener loopback on `127.0.0.1`), uploads into a named folder (default `Snapzy`, cached folder ID), multipart for ≤5 MB else resumable, sets anyone-with-link reader permission. Lifecycle/expiration **unsupported** (`setExpiration`/`removeExpiration` are no-ops) → expire time forced to permanent for this provider.
- `ImgbbCloudProvider`: one multipart `POST https://api.imgbb.com/1/upload` per image. The API key and optional `expiration` (seconds, from `CloudExpireTime`; omitted for permanent) go in the form body, never the URL. Images only (`image/*`) and at most 32 MB (`ImgbbCloudProvider.maxFileSize`); videos and larger files are rejected before any request with `CloudError.unsupportedFileType` / `.fileTooLarge`. The public URL is imgbb's direct link (`data.url`), the history key is `data.id`, and `data.delete_url` is stored as the record's `deleteURL`. imgbb can't overwrite, so `existingKey` is ignored and every re-upload is a new link. There is no delete API: `delete(key:)`, `setExpiration` and `removeExpiration` are no-ops. Save & Test posts the key with no image: error code 100 means a bad key, and the "empty upload source" error (code 130) means imgbb accepted the key, so validation never creates an image. Any other answer (rate limit, outage) fails the test. Cancelling the upload task cancels the request. Re-uploads from Annotate, Quick Access and Video Editor keep the old imgbb history row (`deleteByKey` skips imgbb), because it holds the only link to that image's delete page. `CloudProviderType.usesObjectStorage` is false for imgbb and Google Drive, which hides usage stats and share link style and skips lifecycle rules.
- `CloudManager` (`CloudManager.swift`): facade — non-secret config in UserDefaults (`cloud.*` keys), secrets in Keychain, upload orchestration with `isUploading`/`uploadProgress`, history record insert, thumbnail generation (200 px max-dimension JPEG in `Application Support/Snapzy/thumbnails/<recordUUID>.jpg`; video uploads get frame thumbnails).

## Credentials & secrets

- `CloudKeychainStore`: service `com.trongduong.snapzy.cloud`; items `accessKey`, `secretKey`, `passwordHash`, `googleRefreshToken`, `googleClientId`, `googleClientSecret`, `imgbbAPIKey`. imgbb has only the API key (`CloudManager.credentialItems(for:)` returns no secret item); `.snapzycloud` archives carry it in `accessKey` with an empty `secretKey`. Legacy service `com.snapzy.cloud` auto-migrated. Data-protection keychain primary, file (legacy) keychain fallback when `errSecMissingEntitlement`.
- Protection password (`CloudPasswordService`): optional; SHA-256 hash in Keychain; min 4 characters; gates Edit / Import / Export of the config. Forgot password → reset configuration (`cloudPasswordEnabled` / `cloudPasswordSkipped` flags).
- Encrypted transfer archives (`CloudCredentialTransferService`): `.snapzycloud` files — AES-GCM-256 with PBKDF2-SHA256 key derivation, 300,000 iterations; passphrase ≥ 12 characters.

## Configuration UI (Settings → Cloud)

`PreferencesCloudSettingsView.swift` (+ import/export sheets):

- Provider picker (AWS S3 / Cloudflare R2 / Google Drive / imgbb).
- S3/R2: access key + secret key, bucket, region (S3) or endpoint (R2), optional custom domain.
- Google Drive: client ID + secret + OAuth authorize, folder name.
- imgbb: API key (secure field, "Get an API key" link to `api.imgbb.com`) and expiration. The form and the configured summary both show a warning that imgbb links are public, plus a note that deleting opens imgbb's delete page and that imgbb takes images up to 32 MB, not videos.
- Expire time: 1/3/7/14/30/60/90 days or **permanent** (`CloudExpireTime`). Non-permanent writes the bucket lifecycle rule `snapzy-auto-expire` on the `snapzy/` prefix (`CloudManager.applyLifecycleRule`); permanent warns and removes the rule. Google Drive forced to permanent.
- Optional protection password on save.
- Save & Test: `validate()` credentials before persisting.
- Configured state: masked summary (access key masked, "stored securely in Keychain") + Edit (password-gated) / Import / Export (`.snapzycloud`) / Reset.
- Usage stats grid (`CloudUsageService`): ListObjectsV2 scan of the `snapzy/` prefix, 10-minute cache (`cloud.usageStatsCache`), monthly cost estimates — R2 $0.015/GB (10 GB free), S3 $0.023/GB (5 GB free); skipped for Google Drive.
- Share link style pref (S3/R2, shown once configured): `cloud.shareLinkStyle` (`CloudShareLinkStyle`), `descriptive` by default. `short` hides the file name and capture time from new links. Video Editor re-uploads keep their key. Annotate and Quick Access re-uploads use a new key in the current style and delete the old object, so a link shared before the re-upload stops working. Google Drive is unaffected. Carried in `.snapzycloud` archives (optional `shareLinkStyle`, applied after Save & Test; older archives and unknown values are ignored) and cleared by Reset.
- Uploads window position pref: `cloud.uploads.floatingPosition` (`CloudUploadFloatingPosition`).

## Cloud Uploads window

- `CloudUploadHistoryWindowController` (`PreferencesCloudUploadHistoryView.swift`): 1040×680 floating panel (`panelSize`).
- Open via: menu bar → Cloud Uploads (enabled only when `CloudManager.isConfigured`), ⇧⌘L, `snapzy://open/cloud-uploads`.
- Browse / search / filter (status active-expired, provider, expire time) / sort.
- Per-card actions: copy link, open URL, delete (`CloudManager.deleteFromCloud` — deletes cloud object + history record + thumbnail). imgbb records have no delete API: delete opens the stored `deleteURL` page in the browser, where the user confirms, and removes the local record.
- Clear-all: **Delete from cloud and clear** vs **Clear history only**. Bulk delete skips imgbb records (one browser tab per image would flood the browser), so imgbb images stay online until they expire or the user deletes them on imgbb.
- No upload button inside the window — uploads originate from capture surfaces only.

## Upload history storage

- GRDB `snapzy.db` via `CloudUploadHistoryStore`; table `cloudUploadRecord` (migration `v1_createCloudUploadRecords` in `DatabaseManager`).
- `CloudUploadRecord` fields: `id` (UUID), `fileName`, `publicURL`, `key`, `fileSize`, `uploadedAt`, `providerType`, `expireTime`, `contentType?`, `deleteURL?` (imgbb delete page; migration `v3_addCloudUploadDeleteURL`).
- Derived: `isExpired` (local check from `expireTime.seconds`), `isImageType`, `thumbnailURL`.

## Security boundaries

- Secrets never leave the Keychain except via explicit, passphrase-encrypted `.snapzycloud` export.
- TOML config export excludes secrets — see [CONFIGURATION.md](CONFIGURATION.md).
- Public URLs are bearer links (custom domain / presigned-style path); deletion requires the stored credentials.
- imgbb links are public image URLs on imgbb's servers. Settings says so before the key is saved. The imgbb delete page link is stored only in the local history database.

## Related docs

- [PREFERENCES.md](PREFERENCES.md) — Cloud tab + after-capture matrix (auto-upload removal)
- [SHORTCUTS.md](SHORTCUTS.md) — ⇧⌘L and `snapzy://open/cloud-uploads`
- [QUICK_ACCESS.md](QUICK_ACCESS.md) — card action slots
- [ANNOTATE.md](ANNOTATE.md) — ⌘U upload + re-upload flow
- [VIDEO_EDITOR.md](VIDEO_EDITOR.md) — editor upload + post-export offer
- [HISTORY.md](HISTORY.md) — context-menu uploads
- [UPDATES.md](UPDATES.md) — diagnostics (cloud category logging)
- [CONFIGURATION.md](CONFIGURATION.md) — TOML export excludes secrets
