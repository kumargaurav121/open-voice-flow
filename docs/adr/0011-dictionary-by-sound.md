# 11. Custom dictionary: respell by sound, not by Whisper prompt

Status: Accepted · 2026-10-09

## Context
The dictionary (SPEC §4.6) was planned as Whisper's initial prompt plus LLM cleanup context. Trying it
(docs/eval/reports/2026-10-09-dictionary.md): WhisperKit 0.18 empties the transcript when a prompt is set
(fixed upstream in 1.1.0); on 1.1.1 the prompt helps turbo but costs ~15 ms per prompt token on every
dictation, and the Hinglish model, a fine-tune, ignores it. Hinglish mode is the default, and it's where
names come out wrong ("gurujit", "Gurjit" for Gurjeet).

## Decision
- After speech-to-text and before cleanup, a deterministic step respells anything that **sounds like** a
  dictionary term (`DictionaryCorrection`): a word or up to three adjacent words, compared on a sound key
  (spelling variants merged, vowels weighted half), within a tolerance that grows with the term's length.
  To leave ordinary words alone (a wrongly changed word is worse than a missed name): short terms (under
  five sounds) must sound identical and match one word only; the first sound and last consonant must
  match; and a word macOS's spell checker knows as ordinary English (checked lowercased against plain
  `en`, since en_IN and capitalised forms accept names like "Gurjit") is never respelled. Both modes, no
  added latency, works with any speech model or provider.
- The dictionary is also given to the AI cleanup as spelling context.
- No Whisper prompt; WhisperKit stays on 0.18.

## Consequences
Names the model hears roughly right get fixed reliably, whichever model runs. Words it hears as something
quite different ("WhatsApp" for Vercel) aren't fixed; per-term "sounds like" aliases or learning from the
user's corrections (ROADMAP v2) would cover those. Revisit the prompt if a future Hinglish model honours it.
