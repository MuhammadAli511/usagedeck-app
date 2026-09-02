import CryptoKit
import Foundation

/// One Claude Code config directory that holds a signed-in account.
struct ClaudeConfigDir: Equatable, Sendable {
    /// Absolute path to the config directory.
    let path: String
    /// Human label derived from the directory name when the account cannot name itself:
    /// `~/.claude-beaj` reads "Beaj". `nil` for a plain `~/.claude`, which is just "Claude".
    let fallbackLabel: String?

    init(path: String) {
        self.path = path
        self.fallbackLabel = Self.label(fromDirectoryNamed: (path as NSString).lastPathComponent)
    }

    /// `.claude-beaj` reads "Beaj"; `.claude-side-project` reads "Side Project".
    private static func label(fromDirectoryNamed name: String) -> String? {
        guard name.hasPrefix(".claude-") else { return nil }
        let suffix = String(name.dropFirst(".claude-".count))
        guard let suffix = suffix.nilIfEmpty else { return nil }
        return suffix
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

/// Finds every Claude Code config directory on this machine that holds a signed-in account.
///
/// Claude Code writes each config directory's credentials to the keychain under
/// `Claude Code-credentials-<8 hex of SHA256(absolute path)>`, so the presence of that item is a
/// precise definition of "an account is signed in here". That is what makes discovery safe to run
/// over a `~/.claude*` glob: sibling directories that are not accounts (a worktrees directory, a
/// dated backup) simply have no keychain item and drop out, with no name blocklist to maintain.
struct ClaudeConfigDirDiscovery: Sendable {
    var homeDirectory: @Sendable () -> URL
    var listDirectories: @Sendable (URL) -> [String]
    var keychain: KeychainAccessing
    var environment: EnvironmentReading

    func discover() -> [ClaudeConfigDir] {
        let home = homeDirectory()
        let defaultPath = defaultHomePath()
        var results = [ClaudeConfigDir(path: defaultPath)]
        for name in listDirectories(home).sorted() where Self.looksLikeConfigDir(name) {
            let path = home.appendingPathComponent(name).path
            // The default home is already first; the scan must not list it twice.
            guard path != defaultPath, holdsCredentials(path) else { continue }
            results.append(ClaudeConfigDir(path: path))
        }
        return results
    }

    /// `~/.claude` and its `~/.claude-<name>` siblings. The bare default name is included because a
    /// `CLAUDE_CONFIG_DIR` override can point the default elsewhere, leaving `~/.claude` as an
    /// ordinary second account rather than something to skip.
    private static func looksLikeConfigDir(_ name: String) -> Bool {
        name == ".claude" || name.hasPrefix(".claude-")
    }

    /// The default home, resolved exactly as `ClaudeAuthStore` and `DefaultAccountObserver` do:
    /// `CLAUDE_CONFIG_DIR` when exported, else `~/.claude`. A comma-separated list names no single
    /// home, so it falls back rather than guessing which entry is the real one.
    private func defaultHomePath() -> String {
        guard let raw = environment.value(for: "CLAUDE_CONFIG_DIR")?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
              !raw.contains(",")
        else {
            return homeDirectory().appendingPathComponent(".claude").path
        }
        return expandTilde(raw)
    }

    private func expandTilde(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return homeDirectory().path + String(path.dropFirst(1))
    }

    private func holdsCredentials(_ configDir: String) -> Bool {
        let service = "Claude Code-credentials-\(Self.hashSuffix(configDir))"
        let stored = try? keychain.readGenericPassword(service: service)
        return (stored ?? nil)?.nilIfEmpty != nil
    }

    /// Mirrors `ClaudeAuthStore.hashSuffix`: the first 8 hex characters of the SHA256 of the
    /// canonically precomposed path, which is the suffix Claude Code itself uses.
    static func hashSuffix(_ value: String) -> String {
        let normalized = value.precomposedStringWithCanonicalMapping
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(8))
    }

    /// The real machine: the user's home, its directory listing (hidden entries included, since
    /// every Claude config directory is dot-prefixed), and the login keychain.
    static func live() -> ClaudeConfigDirDiscovery {
        ClaudeConfigDirDiscovery(
            homeDirectory: { FileManager.default.homeDirectoryForCurrentUser },
            listDirectories: { root in
                let urls = (try? FileManager.default.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: []
                )) ?? []
                return urls.compactMap { url in
                    guard let values = try? url.resourceValues(
                        forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                    ), values.isDirectory == true, values.isSymbolicLink != true else { return nil }
                    return url.lastPathComponent
                }
            },
            keychain: SecurityKeychainAccessor(),
            environment: ProcessEnvironmentReader()
        )
    }
}
