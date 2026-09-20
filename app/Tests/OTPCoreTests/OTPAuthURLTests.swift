import Foundation
import Testing
@testable import OTPCore

@Test func parsesIssuerAndAccountFromLabel() {
    let a = OTPAuthURL.parse("otpauth://totp/Stripe:jane%40example.com?secret=mfcn snw5&issuer=Stripe")
    #expect(a == Account(account: "jane@example.com", secret: "MFCNSNW5", issuer: "Stripe"))
}

@Test func issuerParameterOverridesLabelIssuer() {
    let a = OTPAuthURL.parse("otpauth://totp/Old:me?secret=ABCD&issuer=New")
    #expect(a?.issuer == "New")
    #expect(a?.account == "me")
}

@Test func labelWithoutColonIsTheAccount() {
    let a = OTPAuthURL.parse("otpauth://totp/me?secret=ABCD")
    #expect(a?.issuer == "")
    #expect(a?.account == "me")
}

@Test func plusInQueryMeansSpace() {
    #expect(OTPAuthURL.parse("otpauth://totp/x?secret=ABCD&issuer=Amazon+Web+Services")?.issuer == "Amazon Web Services")
}

@Test func rawSpacesInLabelAreAccepted() {
    let a = OTPAuthURL.parse("  otpauth://totp/Amazon Web Services:root?secret=ABCD  ")
    #expect(a?.issuer == "Amazon Web Services")
    #expect(a?.account == "root")
}

@Test(arguments: [
    "https://example.com/?secret=ABCD",
    "otpauth://hotp/x?secret=ABCD",
    "otpauth://totp/x?issuer=I",
    "otpauth://totp/x?secret=",
    "otpauth://totp/x?secret=NOT-BASE32!",
    "otpauth://totp/x?secret=A",
    "otpauth://totp/%E0%A4%A?secret=ABCD",
    "otpauth://totp/%E0%A4?secret=ABCD",
    "not a url",
    "",
])
func rejectsInvalidURLs(raw: String) {
    #expect(OTPAuthURL.parse(raw) == nil)
}

@Test func importLinesCountsAddedUpdatedSkipped() {
    var list = [Account(account: "a", secret: "OLD", issuer: "I", icon: "🙂")]
    let summary = list.importLines("""
    otpauth://totp/I:a?secret=NEW

    otpauth://totp/J:b?secret=ABCD
    garbage
    otpauth://totp/K:c?secret=1234
    """)
    #expect(summary.added == 1)
    #expect(summary.updated == 1)
    #expect(summary.skipped == 2)
    #expect(summary.text == "1 added, 1 updated, 2 skipped")
    #expect(summary.imported == [AccountIdentity(issuer: "I", account: "a"), AccountIdentity(issuer: "J", account: "b")])
    #expect(list[0].secret == "NEW")
    #expect(list[0].icon == "🙂")
}

@Test func importSkipsURLsWithNoAccountName() {
    var list: [Account] = []
    // Both lines have identity ("Acme", ""), so upserting the second would replace
    // the first one's secret and call it an update
    let summary = list.importLines("""
    otpauth://totp/Acme:?secret=ABCD
    otpauth://totp/?secret=EFGH&issuer=Acme
    """)
    #expect(summary.added == 0)
    #expect(summary.updated == 0)
    #expect(summary.skipped == 2)
    #expect(list.isEmpty)
}

@Test func importSummaryWithNothingValid() {
    var list: [Account] = []
    #expect(list.importLines("\n\n").text == "No valid URLs found.")
}
