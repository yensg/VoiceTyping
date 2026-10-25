# Contributing and maintenance

Use focused branches and pull requests. Run the checks in README before proposing a change. Report the macOS version, hardware, steps, expected/actual behavior and relevant sanitized logs. Never attach private audio, transcripts, model files, credentials or local session notes by default.

Keep recording explicit, transcription local, and insertion separate from submission. Never send Return automatically. Preserve focus checks, cancellation, clipboard protection and nonactivating overlays. Document any change to audio retention or network use.

For UI/hotkey changes, test on a Mac: grant permissions, focus a scratch input, hold Right Option, speak, release, verify the text appears without sending and the overlay disappears. Also test cancellation and focus changes. Automated checks alone do not establish this path.

Before publishing, review the staged diff and run a personal-data scan plus a separate secrets scanner. Do not commit `.planning`, `.dialogue`, `.local`, `fixtures/private`, model files, generated apps or recordings. Review dependency pins deliberately; do not silently change models or make accuracy/speed claims without comparable measurements.

The public release checkout is the publishing source of truth. Private development history is not merged into it. Future changes should be reviewed and committed in the public checkout, or copied as a reviewed patch. GitHub Issues tracks requested work; maintenance runs when a maintainer works on the project, not as an unattended service.
