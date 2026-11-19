# Eval reading script 3: more English

Items 45-64 add English dictations to the eval set (v2 ticket 07). The Parakeet decision rested on 17 English
clips, 605 words, where the two models were 5 words apart: these 20 add 614 more.

- **Short** (45-53, 64): the everyday case, a sentence or two.
- **Medium** (54-60): a message or a question, 10-25 s.
- **Long** (61-63): 40-50 s each. English mode cuts only after 40 s of speech, so these test the cut.

They are ordinary dictation: no spoken punctuation, lists or corrections (those are 38-44).

## How to record

Read every item **in one recording**, in order. Say only the text, not the number, and **pause 3-5 seconds
between items**: the split script separates items on pauses longer than 2.8 s. Use the **MacBook
microphone**, the one you dictate with. Save the recording in `docs/eval/raw/english/`; that folder is
git-ignored because recordings are personal data.

- **QuickTime:**
  1. File → New Audio Recording.
  2. Click the arrow next to the record button and pick the microphone.
  3. Record, then File → Save.
- **Terminal:** `mkdir -p docs/eval/raw/english && ffmpeg -f avfoundation -i ":0" -ac 1 -ar 16000
  docs/eval/raw/english/reading-english-$(date +%Y%m%d).wav`, then Ctrl+C to stop.

How to read:

- **Speak at your normal dictation pace**, with the short pauses you'd make anyway.
- **Say numbers the natural way**, as written: "three thirty", "twelve percent".
- **If you say a word differently, keep going.** Then note which words changed, because the reference has to
  match what you actually said.

Then cut the recording into clips 45-64:
`scripts/eval/split.py docs/eval/raw/english/reading-english-YYYYMMDD.m4a --ids 45-64 --min-silence 2.8 --pad 0.4`.

Each item's **reference** is the text as written.

**Recorded 2026-11-19** (`reading-english-20261119.m4a`): item 59 was skipped, so 19 clips and 607 words. The room
noise sat above the split script's -35 dB, so the pauses were found at -28 dB:
`scripts/eval/split.py docs/eval/raw/english/reading-english-20261119.m4a --ids 45-58,60-64 --pad 0.4 --segments docs/eval/segments/reading-english-20261119.json`.

---

## Short

45. Can you send me the slides before the review at three thirty?

46. The build failed again on the main branch, so I'm rolling back the last commit.

47. I'm running about ten minutes late, start without me.

48. Please add Ananya and Vikram to the design channel.

49. Our sign-up rate went up by twelve percent after we shortened the onboarding.

50. Let's move the retro to Thursday afternoon, since half the team is out on Wednesday.

51. Remind me to renew the domain before the twenty-eighth of February.

52. The invoice for October comes to two thousand four hundred dollars, including tax.

53. I think the bug is in the cache layer, not the database. Can you check the logs from last night?

## Medium

54. Thanks for the quick turnaround, this looks great. Just one small change: can we make the button text a bit larger on mobile?

55. Quick question about the API: does the search endpoint support pagination, or do we fetch everything at once?

56. Hey Arjun, I reviewed your pull request. The logic looks right, but the function is doing too much. Could you split the parsing and the validation into two smaller functions, and add a test for the empty input case?

57. For the offsite, we've booked a hotel in Goa for three nights. Flights leave from Bangalore at six fifteen in the morning, so please be at the airport by five.

58. Our monthly cloud bill dropped from about eighteen thousand to eleven thousand rupees after we moved the background jobs to a smaller server.

59. I'm writing to confirm our meeting next Tuesday at eleven. I'll bring the updated roadmap and the hiring plan for the next quarter.

60. Can you explain the difference between a process and a thread, with a simple example?

## Long

61. Here's my update for today. Yesterday I finished the export feature and fixed two bugs in the settings page. Today I'm working on the sync issue that Meera reported, where notes sometimes show up twice after the phone goes offline. I think it happens when two requests retry at the same time, so I'm adding a check on the server. If that works, I'll ship it to the beta group tomorrow morning. I'm blocked on one thing: I still need access to the analytics dashboard, so if someone can add me, that would be great.

62. Hi Sarah, I wanted to follow up on our conversation about the integration. Our team can start in the second week of January, and we expect the first version to take about six weeks. We'll need read access to your staging environment, and a contact on your side who can answer questions about the data format. I've attached a short document with the scope and the timeline. If anything looks off, let's set up a call this week, so we can sort it out before the holidays. Looking forward to working together.

63. The reason the app feels slow on older laptops is mostly memory. When the speech model and the language model are both loaded, they take about four gigabytes together, and on a machine with eight gigabytes the system starts swapping. One option is to unload the language model when it hasn't been used for a few minutes. Another is to use a smaller model for cleanup, which would be faster but a little less accurate. I'd like to try the first option, because it doesn't change the output at all, and measure how often people notice the extra delay when the model loads again.

## Short, to finish

64. Hey, are we still on for dinner on Saturday? I was thinking of that new Italian place near the station. I can book a table for four at eight, unless you'd rather go somewhere else.
