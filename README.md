<h1 align="center">Amgi</h1>

<p align="center">
  <em>암기 (amgi) — Korean for "memorization"</em>
</p>

<p align="center">
  An open-source, offline-first Anki-compatible iOS flashcard client with sync server support.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white" alt="Swift 6.2">
  <img src="https://img.shields.io/badge/iOS-17%2B-000000?logo=apple&logoColor=white" alt="iOS 17+">
  <img src="https://img.shields.io/badge/Rust-FFI-DEA584?logo=rust&logoColor=white" alt="Rust FFI">
  <img src="https://img.shields.io/badge/License-AGPL--3.0-blue" alt="AGPL-3.0">
</p>

<p align="center">
  English | <a href="./README.zh-CN.md">简体中文</a>
</p>

---

Amgi wraps the official [ankitects/anki](https://github.com/ankitects/anki) Rust backend via C FFI, giving you a native SwiftUI experience backed by the same battle-tested engine that powers Anki Desktop and AnkiDroid. Sync your decks with any compatible sync server (including self-hosted), study with FSRS scheduling, and keep your review history in perfect sync across all your devices.

## Features

- **Anki-Compatible Core** -- Uses the official Anki Rust backend over C FFI for scheduling, database access, imports/exports, card generation, and collection maintenance instead of reimplementing Anki behavior in Swift.
- **Offline-First Study** -- Your collection stays fully usable offline, with local review, editing, browsing, reading, and maintenance workflows available even without a network connection.
- **Flexible Sync** -- Sign in to AnkiWeb or connect to a compatible self-hosted sync server, with normal sync, full upload/download, media sync, progress reporting, and conflict-resolution flows built into the app.
- **Real FSRS, Not a Clone** -- Powered by Anki's official FSRS engine, including deck-level FSRS controls, desired retention tuning, preset management, workload simulation, and parameter optimization.
- **Desktop-Accurate Card Rendering** -- Cards are rendered by Anki's template engine with media support, matching desktop behavior as closely as possible for templates, styling, and review presentation.
- **Deck Management** -- Browse hierarchical decks, inspect new/learn/review counts, create, rename, move, and export decks or subdecks, use swipe actions on deck entries, drag decks into other decks, and manage deck presets and scheduling options.
- **Focused Review Experience** -- Study with Again/Hard/Good/Easy, interval previews, audio replay, typed-answer support, flagging, bury/suspend actions, undo, due-date changes, configurable tap regions (3-row or 3x3 layouts), and in-session note/card editing tools.
- **Configurable AI Workflows** -- Add an AI action to selected-text menus in review, reader, and note-editing flows, connect to OpenAI-compatible chat completions endpoints, manage presets with per-preset model/system prompt/glossary settings, define quick actions, save favorite answers, and turn AI responses into note drafts with field mapping and tags.
- **Powerful Browse & Batch Actions** -- Search across the collection, filter by deck and tag, sort results, lazy-load notes, multi-select items, and run batch actions such as tag edits, deletion, deck moves, notetype changes, export, suspend, and reset-to-new.
- **Rich Note Editing** -- Create and edit notes with real field names from the backend, rich field editing, tag management, media insertion, audio recording, source editing, live card preview before committing changes, and an image optimization workflow with cropping, compression, preset resize targets, and custom longest-side limits that avoid upscaling smaller images.
- **Image Occlusion Support** -- Create and edit image occlusion notes with mask tools for rectangles, ellipses, polygons, and text, integrated directly into the native workflow.
- **Template & Notetype Tools** -- Inspect and edit card templates, CSS, and notetype fields from inside the app, with dedicated management screens for templates and field definitions, including creating new note types, adding card templates, and managing field definitions without leaving the app.
- **Comprehensive Statistics** -- Explore daily stats, review heatmaps, future due forecasts, card counts, stability/difficulty charts, hourly patterns, answer-button breakdowns, retrievability, and retention, with deck filtering and customizable chart order.
- **Integrated Reader** -- Read long-form content sourced from Anki notes or imported EPUB files, track reading progress, manage a bookshelf, and connect reading directly to your study workflow.
- **Dictionary-Powered Lookup** -- Includes Yomitan-style dictionary lookup for both the reader and review flow, plus dictionary import, recommended downloads, updates, enable/disable controls, and local audio options.
- **Import, Export, and Backups** -- Supports collection and deck package import/export, selected-note export, backup creation, file management, database checks, media checks, and empty-card maintenance utilities.
- **Multi-Profile & App Settings** -- Switch between local user profiles and customize theme, language, review behavior, editor options, reader preferences, and home/dashboard presentation.
- **Swift 6.2 Strict Concurrency** -- Built with actor isolation and `Sendable`-aware dependencies throughout the app to keep the Swift side modern, explicit, and race-safe.

## Screenshots

<p align="center">
    <img src="assets/Decks.PNG" width="300" alt="Decks Screen" />
    <img src="assets/Stats.PNG" width="300" alt="Stats Screen" />
    <img src="assets/Books.PNG" width="300" alt="Books Screen" />
    <img src="assets/Browse.PNG" width="300" alt="Browse Screen" />
    <img src="assets/Reading.PNG" width="300" alt="Reading Screen" />
    <img src="assets/Cards.PNG" width="300" alt="Cards Screen" />
    <img src="assets/Decks_2.PNG" width="300" alt="decks_2 Screen" />
    <img src="assets/Stats_2.PNG" width="300" alt="Stats_2 Screen" />
    <img src="assets/Books_2.PNG" width="300" alt="Books_2 Screen" />
    <img src="assets/Cards_2.PNG" width="300" alt="Cards_2 Screen" />
    <img src="assets/Reading_2.PNG" width="300" alt="Reading_2 Screen" />
    <img src="assets/Browse_2.PNG" width="300" alt="Browse_2 Screen" />
</p>





## Architecture

```
SwiftUI Views
    |
@DependencyClient structs
    |
AnkiBackend (Swift wrapper)
    |
C FFI (4 functions)
    |
Rust static library (ankitects/anki)
```

Swift owns the UI. Rust owns everything else -- database, sync, FSRS scheduling, card templates, statistics.

For the full architecture walkthrough, see **[ARCHITECTURE.md](ARCHITECTURE.md)**.

Related documentation:

- **[Anki JS API Guide](docs/Anki-JS-API.en.md)**

## Requirements

| Tool | Version |
|------|---------|
| iOS | 17.0+ |
| Xcode | 16.0+ |
| Rust | 1.92+ (via rustup) |
| protoc | 3.0+ |
| protoc-gen-swift | latest |
| xcodegen | latest |

## Getting Started

### 1. Clone with submodules

```bash
git clone --recursive https://github.com/antigluten/anki-ios.git
cd anki-ios
```

### 2. Install dependencies

```bash
# Rust toolchain
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios-simulator

# Protobuf compiler and Swift plugin
brew install protobuf swift-protobuf

# Xcode project generator
brew install xcodegen
```

### 3. Build the Rust XCFramework

```bash
./scripts/build-xcframework.sh
```

This cross-compiles the Rust bridge for iOS device and simulator, then packages both into `AnkiRustLib.xcframework`. The first build takes several minutes; incremental builds are fast.

### 4. Generate Swift protobuf types

```bash
./scripts/generate-protos.sh
```

### 5. Open in Xcode

```bash
cd AnkiApp && xcodegen generate && cd ..
open AnkiApp/AnkiApp.xcodeproj
```

### 6. Build and Run

Select an iOS Simulator or device, then build and run (Cmd+R).

## Tech Stack

- **UI**: SwiftUI with strict concurrency (Swift 6.2, language mode v6)
- **Dependency Injection**: [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) (`@DependencyClient` struct-closure pattern)
- **Backend**: [ankitects/anki](https://github.com/ankitects/anki) Rust crate via C FFI
- **Serialization**: Protocol Buffers (24 .proto service definitions)
- **Database**: SQLite (owned by Rust backend)
- **Build**: SPM for library modules, xcodegen for the app target

## License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)** because it incorporates [ankitects/anki](https://github.com/ankitects/anki) (copyright Ankitects Pty Ltd), which is also AGPL-3.0. See [LICENSE](LICENSE) for the full license text.

The AGPL requires that if you distribute this software or run it as a network service, you must make the complete source code available under the same license.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines, code style, and the development setup.

## Acknowledgments

- **[Damien Elmes](https://github.com/dae)** and the [ankitects/anki](https://github.com/ankitects/anki) contributors for the Rust backend that powers this app
- **[AnkiDroid](https://github.com/ankidroid/Anki-Android)** for pioneering the Rust backend bridge pattern on mobile
- **[Point-Free](https://www.pointfree.co/)** for [swift-dependencies](https://github.com/pointfreeco/swift-dependencies)
