# macOS Voice Memos Export

A small, local-only command-line tool for finding and exporting recordings from Apple Voice Memos by their visible title.

Voice Memos protects its database and recordings with macOS privacy controls. This project therefore separates a normal `voice-memos` CLI from a signed macOS broker app. The CLI launches the broker through LaunchServices, so Full Disk Access is granted only to `VoiceMemosExport.app`, not to your terminal.

## What it does

- Lists locally known Voice Memos recordings.
- Searches titles using case- and diacritic-insensitive matching.
- Exports one recording, or explicitly exports all matches.
- Preserves the original `.m4a` or `.qta` audio without transcoding.
- Produces machine-readable JSON when requested.

The tool has no network access, opens the Voice Memos database read-only, and only accepts source files that resolve to regular `.m4a` or `.qta` files inside the Voice Memos recordings directory.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`)
- Apple Voice Memos with recordings downloaded locally

No Python runtime or third-party package is required.

## Build and install

Clone the repository, verify the build, and install the CLI:

```bash
git clone https://github.com/polarity-dev/macos-voice-memos-export.git
cd macos-voice-memos-export
make check
make install
```

By default this installs:

- the broker app at `~/Applications/VoiceMemosExport.app`;
- the separate CLI executable at `~/.local/bin/voice-memos`.

Make sure `~/.local/bin` is in your `PATH`. You can override either location:

```bash
make install APP_DIR="$HOME/Applications" PREFIX="$HOME/.local"
```

Then open **System Settings → Privacy & Security → Full Disk Access**, click **+**, and select:

```text
~/Applications/VoiceMemosExport.app
```

The project currently uses an ad-hoc code signature and is distributed from source. Rebuilding or replacing the app may require removing and adding it again in Full Disk Access.

## Usage

```bash
# List recordings
voice-memos list

# Find recordings whose titles contain a phrase
voice-memos search "Project notes"

# Require an exact title
voice-memos search "Project notes" --exact

# Export one unambiguous match
voice-memos export "Project notes" --to ~/Desktop/voice-memos

# Explicitly export every match
voice-memos export "Project notes" --to ~/Desktop/voice-memos --all

# Return structured output
voice-memos search "Project notes" --json

# Display the detected database schema without exposing recording data
voice-memos inspect
```

If an export query matches multiple local recordings, the command exits without copying anything unless `--all` is present or the query is made unambiguous with `--exact`.

Exit status `0` means success, `1` means no usable match or a runtime failure, `2` means the export query was ambiguous, and `64` means invalid command-line usage.

## Export filenames

Exports use the visible title and the recording timestamp, including seconds:

```text
Project notes - 2026-08-03_16-53-27.m4a
```

If that name already belongs to different audio, the tool adds the recording identifier and, if necessary, a numeric suffix. Existing audio is never silently overwritten.

## Privacy and security

Full Disk Access is granted only to the broker app. The unprivileged CLI launches it through macOS LaunchServices and exchanges narrowly scoped JSON requests in a private cache directory.

The broker:

- opens `CloudRecordings.db` with SQLite read-only flags;
- accepts only `inspect`, normalized recording metadata, and staging-by-recording-ID operations;
- never accepts a caller-supplied Voice Memos source path or export destination;
- validates that request and response files are regular files inside its dedicated exchange directory;
- requests only the metadata columns needed for listing and export;
- resolves symlinks before verifying that a source remains inside the Voice Memos recordings directory;
- reads only regular `.m4a` or `.qta` source files;
- stages selected audio under a generated exchange directory.

The CLI copies staged audio to the user-selected destination, applies collision-safe filenames, and removes temporary data. Neither component performs network requests. Any process running as the same macOS user can invoke the broker, so run software under that account only when you trust it; the broker's restricted API prevents arbitrary Full Disk Access reads or writes.

## Limitations

Apple does not publish the internal Voice Memos database schema. The tool detects supported columns at runtime and fails with a clear error when required fields are unavailable, but a future macOS release may require an update.

A recording stored only in iCloud cannot be exported until Voice Memos has downloaded it to the Mac.

## Development checks

```bash
make check
```

This compiles the separate Swift CLI and broker targets, signs and verifies the generated app bundle, and checks the CLI help and version commands. Generated binaries are not committed to Git.

The project is available under the [MIT License](LICENSE).

To remove the local installation:

```bash
make uninstall
```
