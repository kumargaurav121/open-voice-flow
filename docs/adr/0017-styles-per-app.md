# 17. Styles per app

Status: Accepted · 2026-11-22 (v2 ticket 13)

## Context
- **The ticket:** the app in front picks a style.
  - Chat is casual: no final full stop on a short message.
  - Email gets the greeting on its own line, with paragraphs and a sign-off line when AI is on.
  - Code stays untouched. Everything else is unchanged.
  - Each style can be switched off in Settings.
- **The SPEC's order puts the style last:** rules, spoken punctuation, AI, lists, then the style.
- **The AI couldn't lay out an email as things stood:**
  - The guard (ADR 0015) allowed only the line breaks the speaker said.
  - Its 4 s limit was too short: Thorough took 4.1 s on eval item 36 (about 100 words) even without layout.
- **A trial with an email instruction (2026-11-22):**
  - Qwen3-1.7B (Fast) returned the text unchanged.
  - Qwen3-4B (Thorough) put the greeting, paragraphs and sign-off on lines of their own, as asked, in 4.5 s.

## Decision
- **Categories, by bundle ID** (from the apps on the user's Mac and Homebrew's cask definitions):
  - Chat: Slack, Teams (new and classic), Messages, WhatsApp, Discord, Telegram (both builds).
  - Email: Mail, Outlook.
  - Code: the existing code-editor list (`CodeContext`).
  - Other: everything else, including web apps in a browser (out of scope).
  - The pipeline factory reads the app in front once per transcript, when the text is about to go in.
- **Chat** drops the final full stop of a message of one or two sentences. These keep theirs:
  - question and exclamation marks;
  - longer messages;
  - lists, so all of a list's items keep their stops;
  - an ellipsis, and an abbreviation ("p.m.", "e.g.", "etc."). "Mr." doesn't end a sentence, so it isn't counted
    as one.
- **Email, rules (with AI on or off):**
  - **The greeting** goes on its own line with a blank line after it: "Hi Mark,", "Good morning team,", "Dear Mr.
    Sharma,", "Hi,". It must open the dictation and end in a comma. A break the speaker said stays as said.
  - **A sign-off ending the email**, after a sentence, goes after a blank line, with the name on the next line:
    "Thanks, Kumar" becomes "Thanks," then "Kumar". This was the user's choice, since sign-offs are a short
    fixed list.
    - The list: Thanks, Thanks again, Many thanks, Thank you, Best, Best regards, Kind regards, Warm regards,
      Regards, Yours sincerely, Sincerely, Cheers, Take care.
    - A name the greeting used belongs to the reader ("Hi Priya, … Thanks, Priya!"), so it stays with the thanks.
- **Email, AI:**
  - The shared prompt gains an email section, with one example, sent only for email.
  - **The guard's third widening** (the user's choice), for email only:
    - The rewrite may add line breaks and blank lines.
    - Every break the speaker said must stay between the same words. A new line may become a paragraph, but a
      paragraph stays a paragraph.
    - The word checks are unchanged.
    - Texts too long to align (about 500 words) need the same breaks as before.
  - **Email gets 8 s for the AI** instead of 4 (the user's choice).
- **Code:** the raw transcript, as before.
- **Settings → Formatting** has a switch for each of chat, email and code, all on by default. Code was the
  user's choice, so prose can be dictated into a terminal, such as a prompt to Claude Code.
- **Commands are never styled.** The log names the style ("Style: email"), never the text.

## Consequences
- **Eval item 36 as into Mail** (Parakeet, real time; runs `t13-email-*`):

  | AI Cleanup | Release to text | Layout |
  |---|---|---|
  | Off | 0.28 s | Greeting line (rules) |
  | Fast | 2.46 s (AI 2.2 s) | Greeting line; Fast returns the body unchanged |
  | Thorough | 4.99 s (AI 4.7 s) | Greeting line, then two paragraphs; also "laptops, run" and "each week. The pilot" |

- **A sign-off with Thorough**, as into Mail (`--clean-text`, 2.7 s): "…before Friday. Thanks, Kumar" became the
  greeting, one paragraph, then "Thanks," and "Kumar". The guard accepted it.
- **Thanks to the reader with AI on:** Thorough itself turns "Hi Priya, … Thanks, Priya!" into "Thanks," and
  "Priya", as if Priya signed it, and drops the "!". The guard accepts this, and the rules can't undo it. With AI
  off, the rules keep "Thanks, Priya!" together.
- **Other apps are unchanged:** all English clips with Thorough and no app (`t13-final-en-thorough`) match
  ticket 11's run (`p11-final-en-thorough`) on its 36 clips, with the same five rejections.
- **Paragraphs come only with Thorough or Cloud.** Settings says so.
- **Undo Formatting is offered after almost every chat message:** the dropped full stop is formatting. Undo puts
  the full stop back.
- **The guard for other apps is unchanged.** It still compares only the sequence of breaks, so a break the AI
  moves elsewhere with the same count passes there. Email now checks positions.
- **Not detected:**
  - sign-offs in Hindi;
  - a greeting with only lowercase names ("hi mark,");
  - a sign-off name the speech model wrote in lowercase.
