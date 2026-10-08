# Eval reading script

Read every item **in one recording**, in order. Say only the text (not the number). **Pause ~2 seconds between items** — the split script cuts on those pauses. Speak naturally, the way you'd dictate in real life; don't over-enunciate.

Record with:

```sh
# 16 kHz mono WAV; Ctrl+C to stop
ffmpeg -f avfoundation -i ":0" -ac 1 -ar 16000 docs/eval/raw/reading-$(date +%Y%m%d).wav
```

(or QuickTime → New Audio Recording, export as `.m4a`; the split script converts it.)

Recordings are personal data: `docs/eval/raw/` and `docs/eval/clips/` are git-ignored.

Each item's **reference** is the text we expect as final output (Latin script by default). Pure-Hindi items also list a Devanagari reference for the Devanagari setting.

---

## English — short

1. Hey, can we push the standup to eleven thirty tomorrow?
2. I've pushed the fix to the main branch, please pull and test it.
3. The meeting with Gurjeet is on Thursday, the fifteenth of October.
4. Our API latency went from four hundred milliseconds to ninety milliseconds after the change.
5. Please review the pull request before end of day, it touches the authentication flow.

## English — technical & names

6. Deploy the Next.js app to Vercel and check the Supabase logs.
7. We're using WhisperKit, MLX Swift and a Qwen model running locally on the Mac.
8. Send the invoice to Priya, Rohan and Gurjeet, and CC the finance team.

## Hindi — pure

9. मैं आज थोड़ा देर से आऊंगा, ट्रैफिक बहुत ज़्यादा है।
   *Latin:* Main aaj thoda der se aaunga, traffic bahut zyada hai.
10. क्या आप मुझे कल की मीटिंग के नोट्स भेज सकते हैं?
    *Latin:* Kya aap mujhe kal ki meeting ke notes bhej sakte hain?
11. खाना तैयार है, सब लोग नीचे आ जाओ।
    *Latin:* Khaana taiyaar hai, sab log neeche aa jao.
12. मुझे लगता है कि हमें इस फीचर को अगले हफ्ते तक टाल देना चाहिए।
    *Latin:* Mujhe lagta hai ki hamein is feature ko agle hafte tak taal dena chahiye.

## Hinglish — mixed

13. Bhai, kal ka demo ready hai kya? Client ko eleven baje dikhana hai.
14. Maine PR raise kar diya hai, bas ek baar review kar lo.
15. Yaar build fail ho raha hai, shayad dependency version ka issue hai.
16. Aaj lunch ke baad ek quick call kar lete hain, around three PM.
17. Gurjeet ko bolo ki design file Figma pe update kar de.
18. Production pe deploy mat karna abhi, pehle staging pe test karo.
19. Mera laptop restart ho gaya aur saara unsaved kaam chala gaya, bahut frustrating hai.
20. Weekend pe plan kya hai? Chalo kahin bahar chalte hain.

## Long-form dictation

21. I wanted to give a quick update on the dictation project. The core pipeline is working end to end: we capture audio, transcribe it locally, clean it up with a small language model and paste it into whatever app is in focus. The next step is the notch animation and then the Slack command.
22. Toh basically plan yeh hai ki pehle hum dictation ko solid banayenge, uske baad commands pe kaam karenge. Slack wala action sabse pehle aayega, aur baaki apps baad mein add honge jab architecture stable ho jaaye.
23. Hi team, just a reminder that the office will be closed on Friday for Diwali. Please wrap up your pending tasks by Thursday evening, and if anything is urgent, message me on Slack. Happy Diwali in advance!

## Commands (read as if holding the command key)

24. Message Gurjeet saying I'll be late by fifteen minutes.
25. Send a message to Priya on Slack: can you share the deck?
26. Gurjeet ko message karo ki main meeting mein hoon, baad mein call karta hoon.
27. Tell Rohan the build is green and he can merge now.
28. Slack pe Priya ko bolo ki lunch ke liye ready ho jaaye.

---

**Expected parse for commands** (used to score intent parsing):

| # | app | to | text |
|---|---|---|---|
| 24 | slack | Gurjeet | I'll be late by fifteen minutes. |
| 25 | slack | Priya | Can you share the deck? |
| 26 | slack | Gurjeet | Main meeting mein hoon, baad mein call karta hoon. |
| 27 | slack | Rohan | The build is green and you can merge now. |
| 28 | slack | Priya | Lunch ke liye ready ho jao. |

Feel free to swap names (Priya, Rohan) for real teammates — update the references to match.
