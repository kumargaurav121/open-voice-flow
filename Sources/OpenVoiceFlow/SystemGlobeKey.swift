import Core
import Foundation

/// The real "Press 🌐 key to" setting for `GlobeKeyAction`. Changed through `TISUpdateFnUsageType`, what
/// System Settings itself calls, so it applies straight away (writing the preference directly would only
/// take effect at the next login). It isn't public API: if a macOS release drops it, the app leaves the
/// setting alone and logs why.
@MainActor
enum SystemGlobeKey {
    private typealias Get = @convention(c) () -> Int32
    private typealias Update = @convention(c) (Int32) -> Void

    private static let domain = "com.apple.HIToolbox" as CFString
    private static let key = "AppleFnUsageType" as CFString
    private static let savedKey = "globeKeyOriginal"

    private static let calls: (get: Get, update: Update)? = {
        guard let carbon = dlopen("/System/Library/Frameworks/Carbon.framework/Carbon", RTLD_LAZY),
              let get = dlsym(carbon, "TISGetFnUsageType"),
              let update = dlsym(carbon, "TISUpdateFnUsageType")
        else { return nil }
        return (unsafeBitCast(get, to: Get.self), unsafeBitCast(update, to: Update.self))
    }()

    static var isAvailable: Bool { calls != nil }

    static func action(defaults: UserDefaults = .standard) -> GlobeKeyAction {
        GlobeKeyAction(
            current: { calls?.get() },
            update: { calls?.update($0) },
            keyExists: {
                // Read fresh: preferences of another domain are cached for the life of the process.
                CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                return CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) != nil
            },
            clearKey: {
                CFPreferencesSetValue(key, nil, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            },
            load: { defaults.data(forKey: savedKey).flatMap { try? JSONDecoder().decode(GlobeKeyAction.Saved.self, from: $0) } },
            save: { saved in
                if let saved, let data = try? JSONEncoder().encode(saved) {
                    defaults.set(data, forKey: savedKey)
                } else {
                    defaults.removeObject(forKey: savedKey)
                }
            }
        )
    }
}
