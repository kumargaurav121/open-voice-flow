import Core
import Foundation
import Testing
@testable import STT

struct DecodingSetupTests {
    let hinglishModel = SpeechModel.hinglish(folder: URL(filePath: "/models/oriserve-hinglish"))

    @Test func hinglishModelForcesEnglishTokenBecauseHindiTokenBreaksItsEnglish() {
        // Bake-off: Oriserve with <|en|> scored the same as auto-detect; with <|hi|> English hit 121% WER.
        #expect(DecodingSetup(language: .hinglish, model: hinglishModel).languageCode == "en")
    }

    @Test func hinglishModelNeverUsesThePrefillCache() {
        // Our conversions ship without prefill data.
        #expect(Language.allCases.allSatisfy { !DecodingSetup(language: $0, model: hinglishModel).usesPrefillCache })
    }

    @Test func turboForcesEnglishForEnglishMode() {
        let setup = DecodingSetup(language: .english, model: .turbo)

        #expect(setup.languageCode == "en")
        #expect(setup.usesPrefillCache)
    }

    @Test func turboDetectsTheLanguageWhenStandingInForHinglish() {
        // Fallback when the Hinglish model isn't installed: forcing hi on turbo breaks its English.
        #expect(DecodingSetup(language: .hinglish, model: .turbo).languageCode == nil)
    }
}

struct HinglishModelFolderTests {
    @Test func aFolderNeedsTheModelsAndItsTokenizer() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        for model in ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"] {
            try FileManager.default.createDirectory(at: folder.appending(path: model), withIntermediateDirectories: true)
        }

        #expect(!SpeechModel.isHinglishModelInstalled(at: folder))

        try Data("{}".utf8).write(to: folder.appending(path: "tokenizer.json"))
        #expect(SpeechModel.isHinglishModelInstalled(at: folder))
    }
}
