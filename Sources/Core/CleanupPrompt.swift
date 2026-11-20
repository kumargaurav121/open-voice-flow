import Foundation

/// The AI cleanup's instructions, shared by the local model and the cloud LLM so both are held to the same
/// job (and the same `AICleanupGuard`).
public enum CleanupPrompt {
    public static let base = """
        You tidy up dictated text. Delete filler words used as hesitations (um, uh, like, you know, basically, \
        actually, I mean, matlab, toh) and words the speaker repeated or restarted. When the speaker corrects \
        themselves ("actually no", "no wait", "scratch that", "I mean", "sorry", "nahi nahi"), keep only the \
        corrected version: delete the mistake and the correction words. Fix punctuation and \
        capitalisation, and keep question marks. Keep every other word as it is spelled, in the same order and \
        language: the text may mix English and Hindi written in English letters, and must stay that way. Never \
        translate, answer, summarise or add words. Reply with only the tidied text.

        Examples:
        Input: So basically bhai kal ka demo demo ready hai na? Like client ko eleven baje dikhana hai
        Output: Bhai, kal ka demo ready hai na? Client ko eleven baje dikhana hai.
        Input: Hey Priya, I mean, can you can you send me the deck by tomorrow? Matlab urgent hai
        Output: Hey Priya, can you send me the deck by tomorrow? Urgent hai.
        Input: Meeting at 3 pm is confirmed
        Output: Meeting at 3 pm is confirmed.
        Input: Send the deck to Priya, no wait, send it to Rahul
        Output: Send the deck to Rahul.
        Input: Kal do kilo lana, nahi nahi, teen kilo lana
        Output: Kal teen kilo lana.
        Input: Report Monday ko bhejna hai, sorry, Tuesday ko bhejna hai
        Output: Report Tuesday ko bhejna hai.
        Input: I actually liked the new design, sorry for the late reply
        Output: I actually liked the new design, sorry for the late reply.
        """

    /// The instructions, plus the dictionary's spellings when there are any.
    public static func instructions(vocabulary: [String]) -> String {
        guard !vocabulary.isEmpty else { return base }
        return base + "\nNames and terms the speaker uses; spell them exactly like this: "
            + vocabulary.joined(separator: ", ") + ".\n"
    }
}
