import Foundation
import Testing
@testable import OTPCore

@Test func accountJSONMatchesElectronShape() throws {
    let a = Account(account: "jane@example.com", secret: "ABC", issuer: "Stripe")
    let json = String(decoding: try JSONEncoder().encode(a), as: UTF8.self)
    #expect(json.contains("\"account\":\"jane@example.com\""))
    #expect(!json.contains("hidden"))
    #expect(!json.contains("icon"))

    var hidden = a
    hidden.hidden = true
    hidden.iconCheckedAt = 1_700_000_000_000
    let decoded = try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(hidden))
    #expect(decoded == hidden)
}

@Test func accountDecodesElectronJSONWithMissingOptionals() throws {
    let json = #"[{"account":"a","secret":"S","issuer":"I","hidden":true,"iconCheckedAt":1700000000000}]"#
    let decoded = try JSONDecoder().decode([Account].self, from: Data(json.utf8))
    #expect(decoded.first?.hidden == true)
    #expect(decoded.first?.iconCheckedAt == 1_700_000_000_000)
    #expect(decoded.first?.icon == nil)
}

@Test func labelOmitsEmptyIssuer() {
    #expect(Account(account: "a", secret: "S", issuer: "").label == "a")
    #expect(Account(account: "a", secret: "S", issuer: "GitHub").label == "GitHub: a")
}

@Test func normalizeSecretStripsWhitespaceAndUppercases() {
    #expect(Account.normalizeSecret(" abcd efgh\tijkl\n") == "ABCDEFGHIJKL")
}

@Test func secretValidation() {
    #expect(Account.isValidSecret("JBSWY3DPEHPK3PXP"))
    #expect(!Account.isValidSecret("JBSWY3DP1"))
    #expect(!Account.isValidSecret(""))
}

@Test func faviconSourcePrefersURLThenIssuerThenAccount() {
    #expect(Account(account: "a", secret: "S", issuer: "I", url: "https://x.com").faviconSource == "https://x.com")
    #expect(Account(account: "a", secret: "S", issuer: "I", url: "").faviconSource == "I")
    #expect(Account(account: "a", secret: "S", issuer: " ").faviconSource == "a")
}

@Test func accountIconDistinguishesEmojiImageAndNone() {
    #expect(AccountIcon(nil) == .none)
    #expect(AccountIcon("") == .none)
    #expect(AccountIcon("🔑") == .emoji("🔑"))
    #expect(AccountIcon("data:image/png;base64,AQID") == .image(Data([1, 2, 3])))
}

@Test func upsertAddsNewAccounts() {
    var list: [Account] = []
    let (stored, result) = list.upsert(Account(account: "a", secret: "S", issuer: "I"))
    #expect(result == .added)
    #expect(list == [stored])
}

@Test func upsertMergeKeepsExistingIconURLAndHidden() {
    var list = [Account(account: "a", secret: "OLD", issuer: "I", icon: "🔑", url: "https://i.com", hidden: true)]
    let (stored, result) = list.upsert(Account(account: "a", secret: "NEW", issuer: "I"))
    #expect(result == .updated)
    #expect(stored.secret == "NEW")
    #expect(stored.icon == "🔑")
    #expect(stored.url == "https://i.com")
    #expect(stored.hidden)
    #expect(list.count == 1)
}

@Test func upsertMergePrefersEntryIconAndDropsMissMarkerOnceIconExists() {
    var list = [Account(account: "a", secret: "S", issuer: "I", iconCheckedAt: 5)]
    let (kept, _) = list.upsert(Account(account: "a", secret: "S", issuer: "I"))
    #expect(kept.iconCheckedAt == 5)
    let (withIcon, _) = list.upsert(Account(account: "a", secret: "S", issuer: "I", icon: "🙂"))
    #expect(withIcon.icon == "🙂")
    #expect(withIcon.iconCheckedAt == nil)
}

@Test func duplicateIdentityDetection() {
    let a = Account(account: "a", secret: "S", issuer: "I")
    #expect(![a].hasDuplicateIdentities)
    #expect([a, a].hasDuplicateIdentities)
}

@Test func applyIconLookupHitSetsIconAndURL() {
    var list = [Account(account: "a", secret: "S", issuer: "I", iconCheckedAt: 5)]
    let changed = list.applyIconLookup(
        list[0].identity, result: FaviconResult(icon: "data:image/png;base64,AA==", domain: "i.com"),
        recordMiss: true, now: Date()
    )
    #expect(changed)
    #expect(list[0].icon == "data:image/png;base64,AA==")
    #expect(list[0].url == "i.com")
    #expect(list[0].iconCheckedAt == nil)
}

@Test func applyIconLookupMissStampsOnlyWhenAsked() {
    var list = [Account(account: "a", secret: "S", issuer: "I")]
    let ignored = list.applyIconLookup(list[0].identity, result: nil, recordMiss: false, now: Date())
    #expect(!ignored)
    #expect(list[0].iconCheckedAt == nil)
    let stamped = list.applyIconLookup(list[0].identity, result: nil, recordMiss: true, now: Date(timeIntervalSince1970: 2))
    #expect(stamped)
    #expect(list[0].iconCheckedAt == 2000)
}

@Test func applyIconLookupNeverOverwritesAnExistingIcon() {
    var list = [Account(account: "a", secret: "S", issuer: "I", icon: "🙂")]
    let result = FaviconResult(icon: "data:image/png;base64,AA==", domain: "i.com")
    let changed = list.applyIconLookup(list[0].identity, result: result, recordMiss: true, now: Date())
    #expect(!changed)
    #expect(list[0].icon == "🙂")
}
