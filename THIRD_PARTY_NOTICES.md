# Third-party components

- [whisper.cpp](https://github.com/ggml-org/whisper.cpp): MIT, pinned in engine-lock.json. Downloaded during build, not vendored into this repository. Its LICENSE is copied into generated app bundles.
- [OpenAI Whisper](https://github.com/openai/whisper): MIT model/code; the pinned ggml conversion is downloaded separately from the upstream-linked distribution. See engine-lock.json for provenance, size and checksum.
- CMake: build dependency installed in a project-local environment; see its upstream license. Swift/AppKit and Apple SDKs are provided by the user's toolchain.

No MacWhisper or Wispr Flow code, assets or binaries are included.
