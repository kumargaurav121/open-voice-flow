import Foundation

/// Apps where dictation must stay verbatim.
public enum CodeContext {
    static let bundleIDs: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.apple.dt.Xcode", "com.apple.Terminal",
        "com.googlecode.iterm2", "com.todesktop.230313mzl4w4u92" /* Cursor */, "dev.zed.Zed", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "org.alacritty", "com.sublimetext.4", "com.panic.Nova",
    ]
    static let bundlePrefixes = ["com.jetbrains."]

    public static func isCodeEditor(bundleID: String) -> Bool {
        bundleIDs.contains(bundleID) || bundlePrefixes.contains { bundleID.hasPrefix($0) }
    }
}
