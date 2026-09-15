import AppKit
import Foundation

enum IntelliJDiscovery {
    static let bundleIDs = ["com.jetbrains.intellij", "com.jetbrains.intellij.ce", "com.jetbrains.intellij.EAP"]

    static func bundlePath(standardPaths: [String]) -> String? {
        let registered = bundleIDs.compactMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.path
        }
        let toolbox = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/JetBrains/Toolbox/apps")
        return findBundle(candidates: standardPaths + registered, toolboxRoot: toolbox)
    }

    static func findBundle(candidates: [String], toolboxRoot: URL) -> String? {
        if let path = candidates.first(where: isIDEABundle) { return path }
        let fm = FileManager.default
        guard let entries = fm.enumerator(
            at: toolboxRoot, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        for case let url as URL in entries {
            if url.pathExtension == "app" {
                entries.skipDescendants()
                if isIDEABundle(url.path) { return url.path }
            } else if entries.level >= 6 {
                entries.skipDescendants()
            }
        }
        return nil
    }

    private static func isIDEABundle(_ path: String) -> Bool {
        guard let id = Bundle(path: path)?.bundleIdentifier, bundleIDs.contains(id) else { return false }
        return FileManager.default.isExecutableFile(atPath: path + "/Contents/MacOS/idea")
    }
}
