# Translex

Translex is a lightweight, local-first macOS menu-bar utility for English ↔ Vietnamese translation and English speech.

## Requirements

- macOS 26.4 or later
- Xcode 26 / Swift 6.2+
- English and Vietnamese Translation language data installed in macOS when required
- Accessibility permission for reliable cross-app selected-text access

## Architecture

- `TranslexCore`: language direction, lexical normalization, settings, SQLite lexicon, enrichment queue, agent CLI contract.
- `TranslexApp`: AppKit menu-bar lifecycle, Accessibility selection, clipboard fallback, Apple Translation, AVSpeechSynthesizer, popup, Settings.
- `TranslexCLI`: bounded machine-oriented interface to the live local lexicon and enrichment queue.

Normal translation does not depend on the lexicon or enrichment worker.
## Usage

Default shortcuts:

- Translate Selection: `⌘1`
- Speak English Selection: `⌘2`

Settings includes a native-language preference (Vietnamese by default, or English) used to resolve mixed/ambiguous EN/VI selections toward the user's native target language. Both shortcuts are recorded directly in Settings: click a shortcut field, press the desired Command/Option/Control/Shift combination plus a supported key, then Apply. Translex rejects a small set of clearly reserved macOS shortcuts, while Carbon registration remains the runtime authority for conflicts. App-local conflicts cannot be universally discovered. The English system voice and popup duration are also configurable.

Selection uses macOS Accessibility first. If the foreground control does not expose selected text, Translex performs one temporary Copy operation, snapshots the current pasteboard, reads the copied selection, then restores the prior pasteboard contents.

Translation uses Apple's native Translation framework only. If a supported EN/VI language model is not installed, the framework requests the system download on demand and continues the original translation after preparation; there is no remote-service fallback.

English speech uses `AVSpeechSynthesizer` and an installed English system voice. Invoking Translate or Speak with no usable selection shows a small nonactivating `No text selected` toast. Successful translation popups include a `+` action that saves the source/translation pair to local Favorites; `Favorites…` in the menu bar lists and removes saved items.
## Local data

The runtime SQLite database is stored at:

`~/Library/Application Support/com.picmao.translex/translex.sqlite3`

SQLite runs with WAL, foreign keys, a busy timeout, and a small migration table. Favorites preserve the original selected source, a deterministic canonical source, and a normalized identity; English single-word favorites use Apple's local NaturalLanguage lemma when one is available. Favorites remain separate from lexical enrichment and duplicate saves are idempotent. Sentence translation never waits for lexical enrichment. Lexical misses are queued once per active normalized identity for later external enrichment.

## Agent CLI

```text
translex queue list [pending|processing|ready|failed]
translex queue claim
translex queue complete <id> < lexeme.json
translex queue fail <id> <message> [--retry]
translex lexeme get <en|vi> <lemma>
translex lexeme upsert < lexeme.json
translex db validate
```

CLI writes validate lexical payloads before committing. Set `TRANSLEX_DB_PATH` to use an alternate database, for example in tests or isolated automation.
## Build and test

```bash
swift build -c debug
swift test
swift build -c release
Scripts/package_app.sh release --install
open /Applications/Translex.app
```

The canonical local workflow signs Translex with the Mac's single available Apple Development identity and safely installs it at `/Applications/Translex.app`. If multiple development identities are available, set `TRANSLEX_SIGNING_IDENTITY` explicitly. Ad-hoc signing is available only as an explicit fallback with `TRANSLEX_ALLOW_ADHOC_SIGNING=1` and is not the preferred installed-app workflow. Notarization and App Store distribution are intentionally out of scope.

Grant Accessibility to the canonical `/Applications/Translex.app` when macOS prompts. Translex uses Accessibility only to read selected text and to support its bounded clipboard-copy fallback; it does not require Screen Recording or Input Monitoring for this workflow. If access is not yet granted, retry the action after granting it; relaunch Translex only if macOS still reports the permission as unavailable.

## Privacy

The normal app path is local. Translex contains no analytics, telemetry, ChatGPT/API integration, crawler, cloud sync, or remote translation fallback. It does not request Photos, Mail, Messages, Contacts, Calendar, Screen Recording, or unrelated Keychain/filesystem access. Arbitrary selected text is not logged by default.

## Known limitations

Cross-app selection depends on the target application's Accessibility behavior; the clipboard fallback cannot guarantee identical semantics for every lazy/custom pasteboard provider. Translation requires Apple's supported EN/VI pair; when language data is missing, Apple may require a one-time model download confirmation. The current build is for local use and is not notarized.
