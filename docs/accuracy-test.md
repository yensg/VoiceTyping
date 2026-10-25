# Same-audio accuracy test

Use the same recording for both engines, with the same language and no cleanup model. Do not record or retain personal speech without the speaker's consent. Put consented test audio and results in gitignored `fixtures/private/`; this is separate from normal temporary dictation.

Start with 15–20 phrases including: “Fail in red”, “MacWhisper”, “Codex”, “GitHub”, ordinary longer sentences, numbers, names, pauses, quiet speech, and silence. Use the user's actual accent. Include mixed-language phrases only if they are part of normal use; compare fixed language against auto detection separately. Do not tune on every evaluation phrase.

For each engine, save one JSONL row per phrase:

```json
{"reference":"Fail in red.","hypothesis":"Fail in bread.","key_terms":["red"]}
```

Run `python3 scripts/score.py fixtures/private/results.jsonl`. Normalization uses Unicode NFKC, case folding, punctuation removal and whitespace word tokenization. WER is total word edits divided by reference words; it can exceed 100%. Chinese without spaces needs a separate character-error metric; this scorer is not suitable for claiming Chinese WER. Report key-term misses as well. Empty-reference rows report insertions but cannot establish a standalone WER.

Record release-to-draft latency separately from engine-only timing. Use multiple alternating trials, same audio and hardware conditions. A 15–20 phrase sample is a smoke test, not proof of accent mastery or a universal model winner.
