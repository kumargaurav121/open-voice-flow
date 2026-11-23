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
  - Email: Mail, Outlook, and mail on the web in a browser (below).
  - Code: the existing code-editor list (`CodeContext`).
  - Other: everything else, including other web apps (Slack in a browser stays unstyled).
  - The pipeline factory reads the app in front once per transcript, when the text is about to go in.
- **Mail on the web** (added 2026-11-23, the user's choices: their email is Gmail in a browser, which the first
  version left unstyled):
  - In Dia, Chrome, Arc, Brave, Safari and Edge, with the email style on, the page in front decides.
  - **By the tab's address, first.** The app asks the browser through AppleScript ("URL of active tab of front
    window"; Safari's "current tab"). Every one of these browsers has the command, Dia included.
    - Gmail is `mail.google.com/mail/…` (or an old work-account link under `/a/`). Its Chat shares the host, under
      `/chat` or as `#chat` in Gmail's own page, and isn't mail.
    - Outlook on the web's mail is `…/mail/…` on outlook.office.com, office365.com, cloud.microsoft and live.com;
      its calendar is under `/calendar`. Outlook's addresses are assumed, not yet seen on the device.
    - A readable address decides, whatever the title says.
  - **Why the address:** the window's title, the first version's signal, changed under the user (2026-11-23).
    - In Chrome, a Gmail dictation matched by its title (an address, then the account's mail name).
    - 21 s later, with a draft open, the title had five parts (25, 4, 17, 6 and 13 characters) and no address.
    - The cause wasn't found. The 13 is likely the " - Google Chrome" Chrome adds for Accessibility.
    - Reading the address through Chrome's web accessibility was rejected: it slows the browser.
  - **The permission:** macOS asks once per browser ("Open Voice Flow wants to control Google Chrome"; entitlement
    `com.apple.security.automation.apple-events`, `NSAppleEventsUsageDescription`).
    - The app checks without asking, and runs the script only when allowed; a hung browser has 1 s to answer.
    - When not yet asked, that dictation uses the title. The prompt comes a second after its text is in, so it
      can't freeze that dictation or take its paste; a dictation that pastes nothing drops it. A dictation started
      while the prompt is up could lose its paste to it.
    - A browser is asked again only if the last ask got no answer (it quit).
    - With the email style off, nothing is read and nothing asked.
  - **By the window's title, when the browser doesn't give the address** (not allowed, or no answer), through
    Accessibility (two calls of at most 0.25 s):
    - an address followed by "Gmail" or a name ending in " Mail" (Gmail's "Inbox (3) - kumar@example.com - Gmail",
      per Google's Workspace Updates blog, 2012; a work account's "… - Acme Mail" is assumed);
    - or "Mail" first and "Outlook" after it (assumed). "Home - Daily Mail" has no address, and Outlook's calendar
      is "Calendar - … - Outlook", so neither is mail.
  - **The log** says why a browser page isn't mail: by its address, or no address and the title's shape (its parts'
    lengths and which part is an address). The permission's status is logged as a number. The address and the
    title never are.
- **Chat** drops the final full stop the speech model gave a message of one or two sentences. These keep theirs:
  - a full stop said out loud ("see you at five full stop"; the user's choice, 2026-11-22);
  - question and exclamation marks;
  - longer messages;
  - lists, so all of a list's items keep their stops;
  - an ellipsis, and an abbreviation ("p.m.", "e.g.", "etc."). "Mr." doesn't end a sentence, so it isn't counted
    as one.
- **Email, rules (with AI on or off):**
  - **The greeting** goes on its own line with a blank line after it: "Hi Mark,", "Good morning team,", "Dear Mr.
    Sharma,", "Hi,". It must open the dictation and end in a comma, or a full stop, which becomes a comma: Parakeet
    and then Thorough left "Hi Mark." after a pause on the user's Mac (2026-11-23). A title's or an initial's full
    stop ("Prof.", "J.") doesn't end it.
    - A break the speaker or the AI put after it stays as it is.
    - The text after it starts with a capital: Thorough left "kal" lowercase.
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
  - Gmail installed as a browser's web app (its own bundle ID), and beta builds of the browsers;
  - Outlook on a company's own server (its address is the company's);
  - sign-offs in Hindi;
  - a greeting with only lowercase names ("hi mark,");
  - a sign-off name the speech model wrote in lowercase.
- **A capitalised first sentence that opens with a greeting word** ("Hey Siri. Set…") goes on a line of its own in
  an email, since "Hi Mark." looks the same.
