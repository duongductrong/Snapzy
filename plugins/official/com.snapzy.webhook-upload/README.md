# Send to Discord

Uploads the capture you run it on to a Discord webhook and copies the resulting
link.

Right-click a capture in Annotate, Quick Access, the Video Editor, or History →
**Send to Discord**. The link lands on your clipboard and in a notification.

## Setup

The first run asks for your webhook URL. It is stored in the **Keychain**, not
in settings, because anyone holding it can post to your channel.

To get one: Discord → Server Settings → Integrations → Webhooks → New Webhook →
Copy Webhook URL.

## What it sends

The capture itself, plus the optional **Message** from settings. It reaches
`discord.com` / `discordapp.com` and nowhere else — that is the whole network
scope in its manifest, shown before you install it.

## Why this plugin exists

Translate exercises every hard subsystem at once. This one is the opposite: one
capability that matters, no document write, no OCR, one outcome. It is about
forty lines of real logic, and it is the honest measure of what a simple Snapzy
plugin costs.

Read `src/main.ts` top to bottom — it fits on one screen.

## Build

```sh
npm install
npm run build          # → main.js
```

`main.js` is committed, because it is the artifact that ships. Rebuild it in the
same change as any edit to `src/`.

## Capabilities

| Capability | Why |
| --- | --- |
| `snapzy.asset.read` | Reads the capture you ran it on |
| `snapzy.network` (`discord.com`, `discordapp.com`) | Uploads it |
| `snapzy.secrets` | Stores the webhook URL in the Keychain |
| `snapzy.ui` *(optional)* | Asks for the URL the first time |
