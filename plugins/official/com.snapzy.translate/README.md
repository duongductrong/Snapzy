# Translate

Reads the text in a screenshot and places translations over the originals as
**one undoable step**.

Open a screenshot in Annotate → right-click → **Translate**. One ⌘Z reverts the
whole thing.

## What it does with your data

1. The text is found **on your Mac**, by the system's Vision recogniser. The
   image never leaves your machine.
2. The recognised **text** — not the image — is sent to the endpoint you
   configured, with your API key.
3. The translations come back and are placed over the original text.

Snapzy has no server in this path and never sees the text, the key, or the
response. The destination is whatever you put in **Endpoint**, and the request
inspector (Settings → Plugins) shows every call it made.

## Settings

| Setting | Default | Notes |
| --- | --- | --- |
| Endpoint | `https://api.openai.com/v1/chat/completions` | Any OpenAI-compatible chat completions endpoint |
| Model | `gpt-4o-mini` | Whatever the endpoint expects |
| Translate into | `English` | Written the way you would say it |
| Placement | `overlay` | `overlay` sits on the original; `callout` sits beneath it |
| Minimum confidence | `0.3` | Skips text the recogniser was unsure about |

The **API key is stored in the Keychain**, not in settings, and is requested by
a host-rendered prompt the first time you run the command.

### Allowed endpoints

The manifest declares the hosts this plugin may reach:

- `api.openai.com`
- `api.anthropic.com`
- `generativelanguage.googleapis.com`
- `openrouter.ai`

That list is shown before you install, and the broker refuses anything outside
it — a wildcard would make the disclosure meaningless. To use a different
provider, fork the plugin, change the `snapzy.network` scope, and load it from
a folder (Settings → Plugins → Development) or publish it as a community
plugin.

## Behaviour worth knowing

- **Running it twice is safe.** Item ids are derived from the source text, so a
  second run over the same screenshot adds nothing instead of stacking
  duplicates.
- **Text shrinks to fit its box** rather than overflowing — an overflowing
  translation covers the thing it is translating.
- **On a surface with no document** (Quick Access, History) it returns the
  translation as text and copies it, instead of failing.
- **If you deny the optional `snapzy.ui` capability** you lose the progress bar
  and the key prompt; everything else still works.

## Build

```sh
npm install
npm run build          # → main.js
```

`main.js` is committed, because it is the artifact that ships. Rebuild it in the
same change as any edit to `src/`.

The build resolves `@snapzy/plugin-sdk` from `sdk/plugin-sdk/` in this
repository via an `--alias` flag. Once the SDK is published to npm, that flag
comes out and the dependency resolves normally.

## Capabilities

| Capability | Why |
| --- | --- |
| `snapzy.asset.read` | Reads the image you ran it on |
| `snapzy.ocr` | Finds the text and its position, locally |
| `snapzy.network` | Sends the text to your configured endpoint |
| `snapzy.document.write` (`addItem`) | Places the translations |
| `snapzy.secrets` | Stores your API key in the Keychain |
| `snapzy.ui` *(optional)* | Key prompt and progress |
