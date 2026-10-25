# VoiceTyping

Free, local dictation for macOS. Hold **Right Option**, speak, and release to insert text into your focused app. VoiceTyping never presses Return for you.

Built with Swift/AppKit and a pinned whisper.cpp engine running Whisper large-v3-turbo locally. No MacWhisper dependency, account, paid transcription API, or usage quota. This is an early source release, not a notarized installer.

## Requirements

- Apple Silicon Mac. Package deployment target: macOS 14; older supported OS versions have not all been tested.
- Swift 6 Command Line Tools and Python 3.12 (the tested build setup).
- Internet for initial dependency/model downloads; transcription then runs locally.
- Disk space for the 1.63 GB model, engine source and build output.
- Microphone and Accessibility permission.

## Build

```sh
git clone https://github.com/yensg/VoiceTyping.git
cd VoiceTyping
python3 scripts/build.py --engine --app
```

Open `dist/VoiceTyping.app`. The builder creates missing folders, installs CMake only in `.local/build-env`, verifies the pinned model checksum, and preserves previous generated bundles. Source/model pins are in `engine-lock.json`.

```sh
python3 scripts/build.py          # create missing folders without overwriting files
python3 scripts/build.py --app    # rebuild using existing engine and model
python3 scripts/build.py --check  # check build outputs
```

Keep the project in place: the app configuration references its local model path. Rebuild after moving it. Builds are ad-hoc signed, so macOS may require permissions again after a rebuild. Accessibility can display an older backup bundle name; select the current `dist/VoiceTyping.app` when refreshing permission.

## Use

1. In Settings, enable Microphone and Accessibility.
2. Select Right Option as the hold key and enable/refresh the shortcut. Shortcuts start disabled on first launch.
3. Focus your destination input, hold Right Option, speak, and release.
4. Keep that input focused until text appears. Review it before sending.

The app stays running behind its waveform menu-bar icon when its window closes. The floating indicator shows recording and transcription, then disappears after the paste attempt. Errors remain visible briefly. Escape cancels while recording; recordings stop after 120 seconds. Avoid assigning the same shortcut to another dictation app.

Settings includes language and vocabulary hints. Voice test has Record/Stop and Cancel buttons; it explicitly retains comparison audio and text in gitignored `fixtures/private/` and does not paste it.

## Privacy and limitations

- No remote inference, telemetry, automatic updater or permanent normal-recording history is implemented.
- Normal recording audio is held in memory, then written temporarily for the engine. Completion/cancellation cleans it up; a crash or force quit can leave temporary files.
- Draft text remains in memory and the clipboard. Restore clipboard works only if another app has not changed it. Language/vocabulary preferences persist locally.
- Pasting uses Cmd+V and is unconfirmed: terminal acceptance cannot be verified. Focus checks distinguish apps, not panes within a terminal. Secure input can block hotkeys.
- Recognition can make mistakes. Silence is energy-gated, but background noise can still produce hallucinations. No broad accent-accuracy or MacWhisper-equivalence claim is made.
- The initial public release is source-only; models, binaries, recordings and private development notes are excluded.

## Development and checks

```sh
swift build --product LocalDictation
swift run PolicyChecks
swift run WorkerChecks
swift run OverlayChecks
swift run InterfaceChecks
python3 -m unittest discover -s scripts -p 'test_*.py'
```

These checks cover policies, helper lifecycle, overlay focus, interface state and build/scoring utilities. They do not replace a real microphone → Right Option → focused-input test. See [CONTRIBUTING.md](CONTRIBUTING.md) and [accuracy testing](docs/accuracy-test.md).

## License

MIT. whisper.cpp and Whisper models have their own upstream MIT notices; the builder includes the whisper.cpp license in generated app bundles. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
