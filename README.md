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

Both shortcuts, the English system voice, and popup duration are configurable in Settings.

Selection uses macOS Accessibility first. If the foreground control does not expose selected text, Translex performs one temporary Copy operation, snapshots the current pasteboard, reads the copied selection, then restores the prior pasteboard contents.

Translation uses Apple's native Translation framework only. If the required language data is supported but not installed, Translex reports that condition instead of falling back to a remote service.

English speech uses `AVSpeechSynthesizer` and an installed English system voice.
## Local data

The runtime SQLite database is stored at:

`~/Library/Application Support/com.picmao.translex/translex.sqlite3`

SQLite runs with WAL, foreign keys, a busy timeout, and a small migration table. Sentence translation never waits for lexical enrichment. Lexical misses are queued once per active normalized identity for later external enrichment.

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
Scripts/package_app.sh release
open build/Translex.app
```

The packaging script builds `build/Translex.app`, generates native icon representations from the supplied canonical PNG, and applies ad-hoc local signing. Notarization and App Store distribution are intentionally out of scope.

## Privacy

The normal app path is local. Translex contains no analytics, telemetry, ChatGPT/API integration, crawler, cloud sync, or remote translation fallback. It does not request Photos, Mail, Messages, Contacts, Calendar, Screen Recording, or unrelated Keychain/filesystem access. Arbitrary selected text is not logged by default.

## Known limitations

Cross-app selection depends on the target application's Accessibility behavior; the clipboard fallback cannot guarantee identical semantics for every lazy/custom pasteboard provider. Translation requires Apple's supported EN/VI pair and installed language assets. The current build is for local use and is not notarized.
