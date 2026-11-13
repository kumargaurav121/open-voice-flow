# Eval reading script 2: long dictations and formatting

Items 29-44 extend the eval set (`reading-script.md` has 1-28). They test three things:

- **Transcribing while you speak** (Hinglish 29-34, English 35-37). Each takes 35-50 s to read.
- **English model bake-off** (35-37, 39, 40, 42, 44).
- **Formatting** (38-44): lists, self-corrections, spoken punctuation, fillers.

## How to record

Read every item **in one recording**, in order. Say only the text, not the number, and **pause 3-5 seconds
between items**: the split script separates items on pauses longer than 2.8 s, so the shorter pauses you
make inside an item stay inside it. Use the **MacBook microphone**, the one you dictate with. Save the
recording in `docs/eval/raw/long/`; that folder is git-ignored because recordings are personal data.

- **QuickTime:**
  1. File → New Audio Recording.
  2. Click the arrow next to the record button and pick the microphone.
  3. Record, then File → Save.
- **Terminal:** `ffmpeg -f avfoundation -i ":0" -ac 1 -ar 16000 docs/eval/raw/long/reading-long-$(date +%Y%m%d).wav`,
  then Ctrl+C to stop.

How to read:

- **Speak at your normal dictation pace.** The short pauses you'd make anyway are wanted: that's where the
  app will cut.
- **For 38-44, read every word exactly as written**, including "comma", "new line", "um" and the corrections.
  Those words are what's being tested.
- **If you say a word differently, keep going.** Then note which words changed, because the reference has to
  match what you actually said.

Then cut the recording into clips 29-44 (`--min-silence 2.8 --pad 0.4`; see `scripts/eval/split.py`). The
current clips come from `reading-long-20261113.m4a`, cut with `docs/eval/segments/reading-long-20261113.json`.

Each item's **reference** is the text as written. For 38-44, **Expected output** is what the formatted
text should look like.

---

## Hinglish: long

29. Haan toh team, aaj ka update de deta hoon. Login wala bug finally fix ho gaya hai, Rohan ne kal raat PR merge kar diya tha. Staging pe sab theek chal raha hai, lekin production pe abhi deploy nahi kiya hai kyunki payment flow ka ek test fail ho raha hai. Main aur Priya aaj lunch ke baad usko dekh lenge. Agar sab theek raha toh shaam tak release kar denge. Ek aur cheez, client ne naya design bheja hai, Gurjeet please usko Figma pe check kar lena aur bata dena ki kitna time lagega. Kal subah standup mein baaki discuss karte hain.

30. Mummy, main is weekend ghar aa raha hoon. Friday raat ki train hai, toh Saturday subah tak pahunch jaunga. Papa ko bol dena ki station lene aane ki zaroorat nahi hai, main auto le lunga. Aur haan, Neha ki birthday ke liye maine ek gift order kiya hai, woh ghar pe deliver hoga, please usko kholna mat. Sunday ko sab log saath mein lunch karte hain, kahin bahar chalenge. Monday subah wapas nikalna padega kyunki office mein ek important meeting hai. Baaki sab theek hai, kaam thoda zyada hai lekin manage ho raha hai.

31. Dekho, problem yeh hai ki jab user app kholta hai toh model load hone mein bahut time lagta hai. Pehli baar toh pandrah minute tak lag jaate hain kyunki macOS model ko Neural Engine ke liye compile karta hai. Uske baad cache ho jaata hai aur kuch seconds mein load ho jaata hai. Mera idea yeh hai ki hum model ko chhota kar dein, taaki download bhi kam ho aur compile bhi jaldi ho. Lekin dhyan rakhna padega ki accuracy kharab na ho. Isliye pehle hum apne eval clips pe test karenge, aur agar word error rate same rehta hai tabhi ship karenge. Agar koi doubt ho toh mujhe Slack pe message kar dena.

32. Yaar trip ka plan final kar lete hain. Hum chaar log hain, toh do rooms book karne padenge. Main soch raha tha ki Friday ko office ke baad nikal jaate hain, around seven PM, aur raat tak Jaipur pahunch jaayenge. Saturday ko fort dekhenge aur shaam ko market chalenge. Sunday subah thoda late uthenge, breakfast ke baad wapas nikal lenge taaki traffic se pehle Delhi pahunch jaayein. Har bande ka budget lagbhag paanch hazaar rupaye aayega, hotel aur petrol milake. Sab log aaj raat tak confirm kar do, phir main booking kar deta hoon.

33. Honestly mujhe lagta hai ki naya onboarding flow pehle se kaafi better hai. Permissions wala step ab clear hai aur user ko pata chalta hai ki kya ho raha hai. Bas ek issue hai, download wale screen pe progress bar kabhi kabhi atak jaata hai, aur user ko lagta hai ki app hang ho gaya. Hum wahan ek chhota sa message add kar sakte hain ki slow internet pe time lag sakta hai. Aur try it wale step mein agar user ko fn key ka pata nahi hai toh woh confuse ho jaata hai. Overall good work, bas yeh do cheezein fix kar do.

34. Hi Priya, kal wali meeting ke notes bhej raha hoon. Client chahta hai ki pehla version December ke end tak ready ho jaaye. Unhone teen cheezein specially boli hain: dashboard fast hona chahiye, mobile pe bhi achha dikhna chahiye, aur reports PDF mein download ho sakein. Maine unko bola hai ki hum next week tak ek rough estimate bhej denge. Tum please design ka pehla draft Wednesday tak share kar dena, aur Rohan backend ka estimate de dega. Agar kuch miss ho gaya ho toh bata dena, main client ko follow up mail bhej dunga.

## English: long

35. Hi everyone, here's a quick summary of where we are this week. The dictation app is now stable for daily use, and the median time from releasing the key to seeing the text is about one and a half seconds. The biggest delay comes from long dictations, because we only start transcribing after you let go. Next, we're going to transcribe while you speak, so that only the last few seconds are left at the end. We're also testing a smaller version of the Hindi model, which should make short dictations faster. If you have feedback, please reply in the thread or send me a direct message.

36. Hi Mark, thanks for your time on the call yesterday. As discussed, we'll start with a two week pilot for your support team, beginning on Monday, the first of December. During the pilot, we'll set up the app on ten laptops, run a short training session, and collect feedback at the end of each week. The pilot is free, and if you decide to continue, we'll send a proposal with annual pricing. Could you please send me the names and email addresses of the people who will take part? Let me know if you have any questions.

37. So the way the new pipeline works is fairly simple. While you're holding the key, the app keeps listening for short pauses in your speech. Every time it finds one, it sends the audio before that pause to the speech model in the background. By the time you let go, most of your dictation has already been transcribed, and only the last part is left. The tricky part is choosing where to cut. If we cut in the middle of a word, the model gets confused, so we only cut when there's at least half a second of silence. We also cut anyway after about twenty five seconds, because the model reads thirty seconds at a time.

## Formatting

38. Kal market se yeh cheezein laani hain. First, doodh. Second, bread. Third, anday. And fourth, paneer.

    **Expected output:**

    ```
    Kal market se yeh cheezein laani hain:
    1. Doodh
    2. Bread
    3. Anday
    4. Paneer
    ```

39. For tomorrow's standup, I have three updates. One, the login bug is fixed. Two, the release notes are ready for review. Three, I'm blocked on the design for the settings page.

    **Expected output:**

    ```
    For tomorrow's standup, I have three updates:
    1. The login bug is fixed.
    2. The release notes are ready for review.
    3. I'm blocked on the design for the settings page.
    ```

40. Let's meet at four, actually no, let's make it five, at the usual coffee place.

    **Expected output:** `Let's meet at five, at the usual coffee place.`

41. Meeting teen baje hai, nahi nahi, chaar baje hai. Main kal Mumbai ja raha hoon, sorry, Pune ja raha hoon.

    **Expected output:** `Meeting chaar baje hai. Main kal Pune ja raha hoon.`

42. Hi Rohan comma new line thanks for the update full stop new paragraph let's ship it on Friday exclamation mark

    **Expected output:**

    ```
    Hi Rohan,
    Thanks for the update.

    Let's ship it on Friday!
    ```

43. Toh basically um main yeh bol raha tha ki ki hum log matlab hum log next week launch kar sakte hain agar agar testing time pe khatam ho jaaye.

    **Expected output:** `Main yeh bol raha tha ki hum log next week launch kar sakte hain agar testing time pe khatam ho jaaye.`

44. I actually enjoyed the demo, the new notch animation looks really smooth.

    **Expected output:** unchanged. Here "actually" isn't a correction, so nothing may be deleted.
