# Custom dictionary before/after, 2026-10-09

28 clips from the personal eval set (see `docs/eval/reading-script.md`), scored against Latin-script references.
WER in %, lower is better. **Agnostic** compares sounds across scripts (Devanagari vs romanised Hindi
count as the same word) and is the headline; **strict** is the text exactly as produced, before cleanup.
Latency is per clip on this Mac outside the app, so compare it between rows, not against the in-app target.

- **app-oriserve-nodict**: in-app run (Swift EvalRunner: silence trim + WhisperKit)
- **app-oriserve-dict**: in-app run (Swift EvalRunner: silence trim + WhisperKit)
- **app-oriserve-thorough-nodict**: in-app run (Swift EvalRunner: silence trim + WhisperKit)
- **app-oriserve-thorough-dict**: in-app run (Swift EvalRunner: silence trim + WhisperKit)
- **app-turbo-en-nodict**: in-app run (Swift EvalRunner: silence trim + WhisperKit)
- **app-turbo-en-dict**: in-app run (Swift EvalRunner: silence trim + WhisperKit)

| Config | Overall WER (agnostic) | Overall WER (strict) | en (agnostic, 227 words) | hi (agnostic, 43 words) | hinglish (agnostic, 158 words) | Median s | p95 s | Translated clips |
|---|---|---|---|---|---|---|---|---|
| app-oriserve-nodict | 17.8 | 22.2 | 16.7 | 9.3 | 21.5 | 0.91 | 1.65 | none |
| app-oriserve-dict | 16.4 | 20.1 | 14.1 | 9.3 | 21.5 | 0.89 | 1.57 | none |
| app-oriserve-thorough-nodict | 18.0 | 22.4 | 16.7 | 9.3 | 22.2 | 2.15 | 3.95 | none |
| app-oriserve-thorough-dict | 16.4 | 20.1 | 14.1 | 9.3 | 21.5 | 2.37 | 4.06 | none |
| app-turbo-en-nodict | 35.3 | 38.6 | 7.0 | 41.9 | 74.1 | 0.92 | 1.80 | 10, 15, 18, 19, 20, 26, 28 |
| app-turbo-en-dict | 37.1 | 39.3 | 6.6 | 53.5 | 76.6 | 0.88 | 1.94 | 10, 11, 15, 18, 19, 20, 26 |

**Strict cross-check.** The agnostic metric is lenient and only helps outputs that use Devanagari, so
here is strict WER where script can't bias the comparison:

| Config | en strict (227 words) | hi strict vs Devanagari refs (43 words) |
|---|---|---|
| app-oriserve-nodict | 18.1 | 100.0 |
| app-oriserve-dict | 15.0 | 100.0 |
| app-oriserve-thorough-nodict | 18.1 | 100.0 |
| app-oriserve-thorough-dict | 15.0 | 100.0 |
| app-turbo-en-nodict | 7.0 | 100.0 |
| app-turbo-en-dict | 6.6 | 100.0 |

## Dictionary findings (ticket 08)

Dictionary used: Gurjeet, Priya, Rohan, Supabase, Vercel, Next.js, WhisperKit, MLX Swift, Qwen, Figma.
`-dict` rows run the app's sound-alike correction (`DictionaryCorrection`, ADR 0011); `-thorough` rows add
the AI cleanup (Qwen3-4B) with the dictionary as context. No Whisper prompt.

- **Hinglish model (Oriserve):** 17.8 → 16.4 agnostic, en items 16.7 → 14.1, no added latency. Every change was a
  correct fix, none touched an ordinary word: Gurjeet on items 3, 8, 17, 24, 26 (was gurujood / gurujit / Gurjit),
  Rohan on 8, Priya on 25 and 28, Next.js on 6, WhisperKit on 7. With Thorough cleanup: 18.0 → 16.4.
- **Turbo (English mode):** en items 7.0 → 6.6; the dictionary's own changes are all correct (Next.js on 6,
  Gurjeet on 17, 24, 26). The row's other differences (empty or reworded clips 10, 11, 15, 28) come from turbo's
  temperature-fallback sampling varying run to run, not from the dictionary.
- **Not fixed (accepted for now):** "Coen" (Qwen) and "priy" (Priya): short terms must sound identical, which keeps
  "ka", "as a", "I am it" safe; "super piece" (Supabase; too far, while "super base" is fixed); "WhatsApp" (Vercel;
  a different word). The AI cleanup with the dictionary as context didn't recover them either.
- **Whisper prompt, tried and dropped:** WhisperKit 0.18 returns empty text when given a prompt
  (argmaxinc/WhisperKit#372, fixed in 1.1.0). On 1.1.1 the prompt fixed turbo's spellings (Qwen, WhisperKit,
  Gurjeet) at ~15 ms per prompt token (+0.5 s for this list), but the Hinglish model ignored it. See ADR 0011.
