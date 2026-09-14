# omarchy-translate

A quick-translate overlay for [Omarchy](https://omarchy.org/). Press `SUPER+T`,
type text, hit `Enter` — the translation appears below, ready to copy.

![Translate overlay in action](screenshots/translate.png)

## Features

- **Overlay summoned with `SUPER+T`** — centered modal card on a scrim, `Esc` or click-outside to dismiss
- **18 languages + auto-detect** as source, 18 as target (English, Spanish, Portuguese, French, German, Italian, Japanese, Chinese, Korean, Russian, Arabic, Hindi, Turkish, Dutch, Polish, Swedish, Ukrainian…)
- **Animated swap button** — swaps source/target, and if there's already a result it swaps the texts and retranslates
- **Copy button with "Copied!" feedback** (copies via `wl-copy`)
- **Detected-language pill**, loading spinner, and inline error states in the output card
- **Character counter** (`n/500`) with clear button and shortcut hints (`↵ Translate · Shift+↵ Newline`)
- **Theme-integrated** — binds to Omarchy's `Color`/`Style` theme tokens, so it follows your theme
- **IPC prefill** — summon with text and it translates immediately:
  `omarchy-shell shell summon carlos.translate '{"text":"ola","source":"pt","target":"en"}'`
- **No API key** — translates through the free MyMemory API

## Requirements

- Omarchy (Hyprland + `omarchy-shell`)
- `wl-copy` (Wayland clipboard), `curl`, `python3`

## Install

### Option A — one command (recommended)

```bash
omarchy plugin add https://github.com/carlosveron/omarchy-translate --enable --yes
```

### Option B — manual

```bash
cp -r omarchy-translate ~/.config/omarchy/plugins/carlos.translate
omarchy-shell shell rescanPlugins
omarchy plugin enable carlos.translate
```

> The plugin is `keepLoaded`, so after editing its QML restart the shell once:
> `omarchy restart shell`

## Keybinding (`SUPER+T`)

`SUPER+T` ships as *toggle window floating/tiling* — unbind it first, in
`~/.config/hypr/bindings.lua`:

```lua
-- SUPER+T opens the translate overlay (was: toggle window floating/tiling).
hl.unbind("SUPER + T")
o.bind("SUPER + T", "Translate", "omarchy-shell shell toggle carlos.translate")
```

Then validate: `hyprctl reload && hyprctl configerrors`.

Optional — make the overlay pop instantly like the stock menu/emoji/clipboard
overlays, in `~/.config/hypr/hyprland.lua`:

```lua
hl.layer_rule({ match = { namespace = "^carlos-translate$" }, no_anim = true, animation = "none" })
```

## Usage

| Action | How |
|---|---|
| Open / close | `SUPER+T` (or `Esc`, or click the scrim) |
| Translate | `Enter` or the Translate button |
| Newline | `Shift+Enter` |
| Swap languages | ⇄ button between the selectors |
| Copy result | Copy button in the output card |
| Clear input | ✕ button inside the input card |

Prefill / script it:

```bash
# Toggle the overlay
omarchy-shell shell toggle carlos.translate
# Open with text (translates immediately), explicit languages optional
omarchy-shell shell summon carlos.translate '{"text":"Good morning!","source":"auto","target":"es"}'
```

## How it works

- `Translate.qml` — overlay UI (panel/overlay plugin, `keepLoaded: true`)
- `bin/translate` — helper: `--to <lang> [--from <lang>] <text>`, always prints
  a single JSON object (`{"ok": true, "translated": …, "source": …}`) parsed from
  `https://api.mymemory.translated.net/get`
- `manifest.json` — plugin manifest (`id: carlos.translate`, kind `overlay`)

Notes:

- MyMemory uses `autodetect` (not `auto`) as the source language — the helper maps it for you.
- The free anonymous quota is limited (~thousands of chars/day per IP) and each request is capped — the UI limits input to 500 chars. Quota/network errors surface inside the output card.
- The plugin id is yours (`carlos.*`); rename the folder + manifest `id` if you fork it.

## License

MIT — do what you want, no warranty.
