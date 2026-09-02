import XCTest
@testable import OpenUsage

/// Claude Code stores each config directory's credentials in the keychain under
/// `Claude Code-credentials-<8 hex of SHA256(absolute path)>`. Discovery treats the presence of that
/// item as the definition of "this directory holds a signed-in account", which is why these tests
/// pin real hash values as literals rather than deriving them with the production helper.
final class ClaudeConfigDirDiscoveryTests: XCTestCase {

    func testDiscoversDefaultHomeEvenWithoutSiblings() {
        let home = URL(fileURLWithPath: "/Users/test")
        let discovery = ClaudeConfigDirDiscovery(
            homeDirectory: { home },
            listDirectories: { _ in [] },
            keychain: ServiceKeychain(values: [:]),
            environment: FakeEnvironment()
        )

        XCTAssertEqual(discovery.discover().map(\.path), ["/Users/test/.claude"])
    }

    func testDiscoversSiblingConfigDirHoldingKeychainCredentials() {
        let home = URL(fileURLWithPath: "/Users/test")
        let discovery = ClaudeConfigDirDiscovery(
            homeDirectory: { home },
            listDirectories: { _ in [".claude", ".claude-beaj"] },
            // SHA256("/Users/test/.claude-beaj") starts 3d6bf7e7
            keychain: ServiceKeychain(values: ["Claude Code-credentials-3d6bf7e7": "{}"]),
            environment: FakeEnvironment()
        )

        XCTAssertEqual(
            discovery.discover().map(\.path),
            ["/Users/test/.claude", "/Users/test/.claude-beaj"]
        )
    }

    func testConfigDirEnvironmentOverrideRelocatesTheDefaultHome() {
        let home = URL(fileURLWithPath: "/Users/test")
        let discovery = ClaudeConfigDirDiscovery(
            homeDirectory: { home },
            listDirectories: { _ in [] },
            keychain: ServiceKeychain(values: [:]),
            environment: FakeEnvironment(["CLAUDE_CONFIG_DIR": "/Users/test/.claude-heyoz"])
        )

        XCTAssertEqual(discovery.discover().map(\.path), ["/Users/test/.claude-heyoz"])
    }

    func testDefaultHomeIsListedFirstAndNeverDuplicatedByTheSiblingScan() {
        let home = URL(fileURLWithPath: "/Users/test")
        let discovery = ClaudeConfigDirDiscovery(
            homeDirectory: { home },
            listDirectories: { _ in [".claude", ".claude-heyoz"] },
            keychain: ServiceKeychain(values: [
                "Claude Code-credentials-462977e4": "{}",  // SHA256("/Users/test/.claude")
                "Claude Code-credentials-b57acb03": "{}",  // SHA256("/Users/test/.claude-heyoz")
            ]),
            environment: FakeEnvironment(["CLAUDE_CONFIG_DIR": "/Users/test/.claude-heyoz"])
        )

        XCTAssertEqual(
            discovery.discover().map(\.path),
            ["/Users/test/.claude-heyoz", "/Users/test/.claude"]
        )
    }

    func testSiblingCarriesTitleCasedFallbackLabelAndDefaultHomeCarriesNone() {
        let home = URL(fileURLWithPath: "/Users/test")
        let discovery = ClaudeConfigDirDiscovery(
            homeDirectory: { home },
            listDirectories: { _ in [".claude", ".claude-beaj"] },
            keychain: ServiceKeychain(values: ["Claude Code-credentials-3d6bf7e7": "{}"]),
            environment: FakeEnvironment()
        )

        let dirs = discovery.discover()
        XCTAssertNil(dirs[0].fallbackLabel, "the default home is just \"Claude\"")
        XCTAssertEqual(dirs[1].fallbackLabel, "Beaj")
    }

    /// The safety property the whole design rests on: a `~/.claude*` directory that is not an
    /// account has no keychain item, so no name blocklist is needed to keep it out.
    func testIgnoresClaudeNamedDirectoriesThatHoldNoCredentials() {
        let home = URL(fileURLWithPath: "/Users/test")
        let discovery = ClaudeConfigDirDiscovery(
            homeDirectory: { home },
            listDirectories: { _ in
                [".claude", ".claude-beaj", ".claude-worktrees", ".claude.bak.20260614-181957"]
            },
            keychain: ServiceKeychain(values: ["Claude Code-credentials-3d6bf7e7": "{}"]),
            environment: FakeEnvironment()
        )

        XCTAssertEqual(
            discovery.discover().map(\.path),
            ["/Users/test/.claude", "/Users/test/.claude-beaj"]
        )
    }

    func testMultiWordDirectorySuffixReadsAsSeparateWords() {
        XCTAssertEqual(
            ClaudeConfigDir(path: "/Users/test/.claude-side-project").fallbackLabel,
            "Side Project"
        )
    }

    /// Pins the hash convention against a suffix observed in a real macOS keychain, so a change to
    /// the derivation cannot silently stop matching Claude Code's own items.
    func testKeychainSuffixMatchesClaudeCodesOwnDerivation() {
        XCTAssertEqual(ClaudeConfigDirDiscovery.hashSuffix("/Users/ali/.claude-beaj"), "99ba68ad")
    }
}
