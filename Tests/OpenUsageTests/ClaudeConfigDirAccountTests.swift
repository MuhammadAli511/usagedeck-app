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

    func testEachSignedInConfigDirBecomesItsOwnCard() async {
        let defaults = makeScratchDefaults()
        let store = ProviderAccountsStore(defaults: defaults)
        let observer = DefaultAccountObserver(
            environment: FakeEnvironment([:]),
            files: FakeFiles([
                "/Users/dev/.claude.json":
                    #"{"oauthAccount": {"accountUuid": "ACCT-1", "emailAddress": "me@example.com"}}"#,
                "/Users/dev/.claude-work/.claude.json":
                    #"{"oauthAccount": {"accountUuid": "ACCT-2", "organizationUuid": "ORG-2", "organizationName": "Work", "emailAddress": "me@work.example"}}"#,
            ]),
            keychain: FakeKeychain(nil),
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") }
        )
        let discovery = ClaudeConfigDirDiscovery(
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") },
            listDirectories: { _ in [".claude", ".claude-work"] },
            // SHA256("/Users/dev/.claude-work") starts 4298c2ba
            keychain: ServiceKeychain(values: ["Claude Code-credentials-4298c2ba": "{}"]),
            environment: FakeEnvironment([:])
        )

        let assembly = await ProviderAccountAssembly.make(
            observer: observer, accountsStore: store, configDirDiscovery: discovery
        )

        XCTAssertEqual(
            assembly.claudeCards.map(\.displayName),
            ["Claude", "Claude · Work"]
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
            configDir: "/Users/dev/.claude-work"
        )

        // SHA256("/Users/dev/.claude-work") starts 4298c2ba
        XCTAssertEqual(store.keychainServiceCandidates().first, "Claude Code-credentials-4298c2ba")
    }

    /// The credential FILE has to follow the config directory too. Reading `~/.claude/.credentials.json`
    /// for an account that lives in `~/.claude-work` would attribute one account's usage to another.
    func testAuthStoreScopedToAConfigDirReadsThatDirectorysCredentialFile() {
        let store = ClaudeAuthStore(
            environment: FakeEnvironment([:]),
            files: FakeFiles([
                "/Users/dev/.claude-work/.credentials.json":
                    #"{"claudeAiOauth":{"accessToken":"work-token","subscriptionType":"max"}}"#,
                "/Users/dev/.claude/.credentials.json":
                    #"{"claudeAiOauth":{"accessToken":"default-token","subscriptionType":"pro"}}"#,
            ]),
            keychain: ServiceKeychain(values: [:]),
            configDir: "/Users/dev/.claude-work"
        )

        XCTAssertEqual(
            store.loadCredentialCandidates().map(\.oauth.accessToken),
            ["work-token"]
        )
    }

    /// The card is what `ProviderCatalog` turns into a live runtime, so it has to carry the config
    /// directory or the per-account auth store and log scanner have nothing to scope themselves to.
    func testConfigDirCardCarriesItsDirectoryAndTheDefaultCardDoesNot() async {
        let defaults = makeScratchDefaults()
        let store = ProviderAccountsStore(defaults: defaults)
        let observer = DefaultAccountObserver(
            environment: FakeEnvironment([:]),
            files: FakeFiles([
                "/Users/dev/.claude.json":
                    #"{"oauthAccount": {"accountUuid": "ACCT-1", "emailAddress": "me@example.com"}}"#,
                "/Users/dev/.claude-work/.claude.json":
                    #"{"oauthAccount": {"accountUuid": "ACCT-2", "organizationUuid": "ORG-2", "organizationName": "Work"}}"#,
            ]),
            keychain: FakeKeychain(nil),
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") }
        )
        let discovery = ClaudeConfigDirDiscovery(
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") },
            listDirectories: { _ in [".claude", ".claude-work"] },
            keychain: ServiceKeychain(values: ["Claude Code-credentials-4298c2ba": "{}"]),
            environment: FakeEnvironment([:])
        )

        let assembly = await ProviderAccountAssembly.make(
            observer: observer, accountsStore: store, configDirDiscovery: discovery
        )

        XCTAssertEqual(
            assembly.claudeCards.map(\.configDir),
            [nil, "/Users/dev/.claude-work"]
        )
    }

    /// The default home is always just "Claude". Titling it with its organization ("Claude \u{00B7} Muhammad
    /// Ali") makes the account you use most read as the odd one out.
    func testDefaultCardStaysPlainClaudeEvenWhenItsAccountHasAnOrganization() async {
        let cards = await makeCards(
            defaultAccount:
                #"{"accountUuid": "ACCT-1", "organizationUuid": "ORG-1", "organizationName": "Muhammad Ali", "emailAddress": "me@example.com"}"#,
            siblingAccount:
                #"{"accountUuid": "ACCT-2", "organizationUuid": "ORG-2", "organizationName": "Acme"}"#
        )

        XCTAssertEqual(cards.map(\.displayName), ["Claude", "Claude \u{00B7} Acme"])
    }

    /// Claude hands a personal account an auto-generated organization name like
    /// "someone@example.com's Organization". That is worse than the directory name in every way, so
    /// it is treated as no name at all.
    func testAutoGeneratedOrganizationNameFallsBackToTheDirectoryName() async {
        let cards = await makeCards(
            defaultAccount: #"{"accountUuid": "ACCT-1"}"#,
            siblingAccount:
                #"{"accountUuid": "ACCT-2", "organizationUuid": "ORG-2", "organizationName": "someone@example.com's Organization"}"#
        )

        XCTAssertEqual(cards.map(\.displayName), ["Claude", "Claude \u{00B7} Work"])
    }

    /// Builds the card list for a default home plus one signed-in `~/.claude-work`.
    private func makeCards(defaultAccount: String, siblingAccount: String) async -> [ClaudeAccountCard] {
        let store = ProviderAccountsStore(defaults: makeScratchDefaults())
        let observer = DefaultAccountObserver(
            environment: FakeEnvironment([:]),
            files: FakeFiles([
                "/Users/dev/.claude.json": #"{"oauthAccount": \#(defaultAccount)}"#,
                "/Users/dev/.claude-work/.claude.json": #"{"oauthAccount": \#(siblingAccount)}"#,
            ]),
            keychain: FakeKeychain(nil),
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") }
        )
        let discovery = ClaudeConfigDirDiscovery(
            homeDirectory: { URL(fileURLWithPath: "/Users/dev") },
            listDirectories: { _ in [".claude", ".claude-work"] },
            keychain: ServiceKeychain(values: ["Claude Code-credentials-4298c2ba": "{}"]),
            environment: FakeEnvironment([:])
        )
        return await ProviderAccountAssembly.make(
            observer: observer, accountsStore: store, configDirDiscovery: discovery
        ).claudeCards
    }
}
