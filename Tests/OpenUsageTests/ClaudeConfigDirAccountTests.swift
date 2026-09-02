import XCTest
@testable import OpenUsage

/// The account pass with more than one Claude config directory signed in: each directory becomes its
/// own account record and its own card, so several Claude subscriptions show side by side.
@MainActor
final class ClaudeConfigDirAccountTests: XCTestCase {
    private func makeScratchDefaults() -> UserDefaults {
        let suiteName = "UsageDeckTests.ClaudeConfigDirAccounts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    func testEachSignedInConfigDirBecomesItsOwnCard() {
        let defaults = makeScratchDefaults()
        let store = ProviderAccountsStore(defaults: defaults)
        let observer = DefaultAccountObserver(
            environment: FakeEnvironment([:]),
            files: FakeFiles([
                "/Users/dev/.claude.json":
                    #"{"oauthAccount": {"accountUuid": "ACCT-1", "emailAddress": "me@example.com"}}"#,
                "/Users/dev/.claude-beaj/.claude.json":
                    #"{"oauthAccount": {"accountUuid": "ACCT-2", "organizationUuid": "ORG-2", "organizationName": "Beaj", "emailAddress": "me@beaj.org"}}"#,
            ]),
            keychain: FakeKeychain(nil),
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") }
        )
        let discovery = ClaudeConfigDirDiscovery(
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") },
            listDirectories: { _ in [".claude", ".claude-beaj"] },
            // SHA256("/Users/dev/.claude-beaj") starts 0d895ea0
            keychain: ServiceKeychain(values: ["Claude Code-credentials-0d895ea0": "{}"]),
            environment: FakeEnvironment([:])
        )

        let assembly = ProviderAccountAssembly.make(
            observer: observer, accountsStore: store, configDirDiscovery: discovery
        )

        XCTAssertEqual(
            assembly.claudeCards.map(\.displayName),
            ["Claude", "Claude · Beaj"]
        )
    }

    /// The whole point of carrying the config directory through to the auth store: Claude Code keeps
    /// each directory's credentials under its own keychain service, so without this an extra account
    /// would silently read the default account's token.
    func testAuthStoreScopedToAConfigDirLooksUpThatDirectorysKeychainItem() {
        let store = ClaudeAuthStore(
            environment: FakeEnvironment([:]),
            files: FakeFiles(),
            keychain: ServiceKeychain(values: [:]),
            configDir: "/Users/dev/.claude-beaj"
        )

        // SHA256("/Users/dev/.claude-beaj") starts 0d895ea0
        XCTAssertEqual(store.keychainServiceCandidates().first, "Claude Code-credentials-0d895ea0")
    }

    /// The credential FILE has to follow the config directory too. Reading `~/.claude/.credentials.json`
    /// for an account that lives in `~/.claude-beaj` would attribute one account's usage to another.
    func testAuthStoreScopedToAConfigDirReadsThatDirectorysCredentialFile() {
        let store = ClaudeAuthStore(
            environment: FakeEnvironment([:]),
            files: FakeFiles([
                "/Users/dev/.claude-beaj/.credentials.json":
                    #"{"claudeAiOauth":{"accessToken":"beaj-token","subscriptionType":"max"}}"#,
                "/Users/dev/.claude/.credentials.json":
                    #"{"claudeAiOauth":{"accessToken":"default-token","subscriptionType":"pro"}}"#,
            ]),
            keychain: ServiceKeychain(values: [:]),
            configDir: "/Users/dev/.claude-beaj"
        )

        XCTAssertEqual(
            store.loadCredentialCandidates().map(\.oauth.accessToken),
            ["beaj-token"]
        )
    }

    /// The card is what `ProviderCatalog` turns into a live runtime, so it has to carry the config
    /// directory or the per-account auth store and log scanner have nothing to scope themselves to.
    func testConfigDirCardCarriesItsDirectoryAndTheDefaultCardDoesNot() {
        let defaults = makeScratchDefaults()
        let store = ProviderAccountsStore(defaults: defaults)
        let observer = DefaultAccountObserver(
            environment: FakeEnvironment([:]),
            files: FakeFiles([
                "/Users/dev/.claude.json":
                    #"{"oauthAccount": {"accountUuid": "ACCT-1", "emailAddress": "me@example.com"}}"#,
                "/Users/dev/.claude-beaj/.claude.json":
                    #"{"oauthAccount": {"accountUuid": "ACCT-2", "organizationUuid": "ORG-2", "organizationName": "Beaj"}}"#,
            ]),
            keychain: FakeKeychain(nil),
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") }
        )
        let discovery = ClaudeConfigDirDiscovery(
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") },
            listDirectories: { _ in [".claude", ".claude-beaj"] },
            keychain: ServiceKeychain(values: ["Claude Code-credentials-0d895ea0": "{}"]),
            environment: FakeEnvironment([:])
        )

        let assembly = ProviderAccountAssembly.make(
            observer: observer, accountsStore: store, configDirDiscovery: discovery
        )

        XCTAssertEqual(
            assembly.claudeCards.map(\.configDir),
            [nil, "/Users/dev/.claude-beaj"]
        )
    }

    /// The default home is always just "Claude". Titling it with its organization ("Claude \u{00B7} Muhammad
    /// Ali") makes the account you use most read as the odd one out.
    func testDefaultCardStaysPlainClaudeEvenWhenItsAccountHasAnOrganization() {
        let cards = makeCards(
            defaultAccount:
                #"{"accountUuid": "ACCT-1", "organizationUuid": "ORG-1", "organizationName": "Muhammad Ali", "emailAddress": "me@example.com"}"#,
            siblingAccount:
                #"{"accountUuid": "ACCT-2", "organizationUuid": "ORG-2", "organizationName": "HeyOz"}"#
        )

        XCTAssertEqual(cards.map(\.displayName), ["Claude", "Claude \u{00B7} HeyOz"])
    }

    /// Claude hands a personal account an auto-generated organization name like
    /// "someone@example.com's Organization". That is worse than the directory name in every way, so
    /// it is treated as no name at all.
    func testAutoGeneratedOrganizationNameFallsBackToTheDirectoryName() {
        let cards = makeCards(
            defaultAccount: #"{"accountUuid": "ACCT-1"}"#,
            siblingAccount:
                #"{"accountUuid": "ACCT-2", "organizationUuid": "ORG-2", "organizationName": "beajeducation@gmail.com's Organization"}"#
        )

        XCTAssertEqual(cards.map(\.displayName), ["Claude", "Claude \u{00B7} Beaj"])
    }

    /// Builds the card list for a default home plus one signed-in `~/.claude-beaj`.
    private func makeCards(defaultAccount: String, siblingAccount: String) -> [ClaudeAccountCard] {
        let store = ProviderAccountsStore(defaults: makeScratchDefaults())
        let observer = DefaultAccountObserver(
            environment: FakeEnvironment([:]),
            files: FakeFiles([
                "/Users/dev/.claude.json": #"{"oauthAccount": \#(defaultAccount)}"#,
                "/Users/dev/.claude-beaj/.claude.json": #"{"oauthAccount": \#(siblingAccount)}"#,
            ]),
            keychain: FakeKeychain(nil),
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") }
        )
        let discovery = ClaudeConfigDirDiscovery(
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") },
            listDirectories: { _ in [".claude", ".claude-beaj"] },
            keychain: ServiceKeychain(values: ["Claude Code-credentials-0d895ea0": "{}"]),
            environment: FakeEnvironment([:])
        )
        return ProviderAccountAssembly.make(
            observer: observer, accountsStore: store, configDirDiscovery: discovery
        ).claudeCards
    }
}
