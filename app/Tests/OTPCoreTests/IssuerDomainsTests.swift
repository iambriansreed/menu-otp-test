import Testing
@testable import OTPCore

@Test(arguments: [
    ("Privacy.com", ["privacy.com"]),
    ("render.com", ["render.com"]),
    ("T-Mobile ID", ["t-mobile.com", "t-mobileid.com"]),
    ("Google Authenticator", ["google.com", "googleauthenticator.com"]),
    ("Google (Work)", ["google.com"]),
    ("ID.me+Wallet", ["id.me"]),
    ("Amazon Web Services", ["amazonwebservices.com", "amazon.com"]),
    ("1Password", ["1password.com"]),
    ("https://www.Example.com/path", ["example.com"]),
    ("www.github.com", ["github.com"]),
    ("Amazon%20Web%20Services", ["amazonwebservices.com", "amazon.com"]),
    ("", []),
    ("   ", []),
    ("日本", []),
])
func domainsForIssuer(issuer: String, expected: [String]) {
    #expect(IssuerDomains.domains(for: issuer) == expected)
}

@Test func looksLikeDomain() {
    #expect(IssuerDomains.looksLikeDomain("id.me"))
    #expect(IssuerDomains.looksLikeDomain("A-B.Example.COM"))
    #expect(!IssuerDomains.looksLikeDomain("localhost"))
    #expect(!IssuerDomains.looksLikeDomain(".com"))
    #expect(!IssuerDomains.looksLikeDomain("a.c"))
}
