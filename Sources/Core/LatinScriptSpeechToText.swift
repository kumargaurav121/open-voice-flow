import Foundation

/// Guarantees transcripts are written in English letters and Western digits, whatever script the model
/// chose: Hindi in Devanagari or Urdu script is transliterated ("मैं आज" → "main aj"), not translated.
/// A safety net under every model; the Hinglish model already writes Roman script on its own.
@MainActor
public final class LatinScriptSpeechToText: SpeechToText {
    private let model: SpeechToText

    public init(wrapping model: SpeechToText) {
        self.model = model
    }

    public func transcribe(_ clip: AudioClip, language: Language) async throws -> String {
        Self.latin(try await model.transcribe(clip, language: language))
    }

    static func latin(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: isIndicOrArabic) else { return text }
        // Only runs of Devanagari or Arabic script are rewritten; everything else, including English
        // punctuation, accents, currency signs and whitespace, is kept exactly.
        var output = ""
        var run = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if isIndicOrArabic(scalar) {
                run.append(scalar)
                continue
            }
            output += transliterate(String(run))
            run.removeAll()
            output.unicodeScalars.append(scalar)
        }
        return output + transliterate(String(run))
    }

    private static func isIndicOrArabic(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0900...0x097F,                         // Devanagari (incl. danda, digits)
             0x0600...0x06FF, 0x0750...0x077F,        // Arabic, incl. Urdu letters and digits
             0xFB50...0xFDFF, 0xFE70...0xFEFF:        // Arabic presentation forms
            return true
        default:
            return false
        }
    }

    private static func transliterate(_ run: String) -> String {
        guard !run.isEmpty else { return "" }
        var prepared = String.UnicodeScalarView()
        for scalar in run.unicodeScalars {
            switch scalar.value {
            case 0x0964, 0x0965, 0x06D4:  // danda, double danda, Urdu full stop
                prepared.append(".")
            case 0x0902:  // Devanagari nasal dot (anusvara) reads as "n" in everyday Roman Hindi: मैं → main
                prepared.append(contentsOf: "\u{0928}\u{094D}".unicodeScalars)
            default:
                if let value = Character(scalar).wholeNumberValue, Character(scalar).isNumber {
                    prepared.append(contentsOf: String(value).unicodeScalars)
                } else {
                    prepared.append(scalar)
                }
            }
        }
        let source = String(prepared)
        var latin = (source.applyingTransform(.toLatin, reverse: false) ?? source)
            .applyingTransform(.stripDiacritics, reverse: false) ?? source
        latin = latin.replacingOccurrences(of: "'", with: "")  // ICU's vowel separators (आऊंगा → a'unga)
        // ICU spells out the silent vowel after a final consonant (देर → dera); everyday spelling drops it.
        if endsInBareDevanagariConsonant(run), let schwa = latin.range(of: "a(?=\\.*$)", options: .regularExpression) {
            latin.removeSubrange(schwa)
        }
        // Leftover marks with no English letter (e.g. ʾ, ʱ from Urdu) are dropped.
        return String(String.UnicodeScalarView(latin.unicodeScalars.filter(\.isASCII)))
    }

    private static func endsInBareDevanagariConsonant(_ run: String) -> Bool {
        // The nukta (़) may follow its consonant as a separate code point; it doesn't add a vowel.
        // Sentence stops after it don't either.
        guard let last = run.unicodeScalars.last(where: { ![0x093C, 0x0964, 0x0965].contains($0.value) }) else { return false }
        return (0x0915...0x0939).contains(last.value) || (0x0958...0x095F).contains(last.value)
    }
}
