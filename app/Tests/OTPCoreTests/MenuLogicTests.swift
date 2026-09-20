import Foundation
import Testing
@testable import OTPCore

private let a = Account(account: "jane", secret: "ABCD", issuer: "GitHub", icon: "🐙")
private let b = Account(account: "root", secret: "ABCD", issuer: "AWS", hidden: true)
private let c = Account(account: "me", secret: "ABCD", issuer: "")

@Test func rowsListVisibleAccountsThenSettingsAndQuit() {
    let rows = MenuRows.build(accounts: [a, b, c], lastClicked: nil, appName: "Menu OTP")
    #expect(rows == [
        MenuRow(kind: .item, label: "GitHub: jane", action: .copy(a.identity), icon: "🐙"),
        MenuRow(kind: .item, label: "me", action: .copy(c.identity)),
        MenuRow(kind: .separator),
        MenuRow(kind: .item, label: "Menu OTP Settings...", action: .settings),
        MenuRow(kind: .item, label: "Quit Menu OTP", action: .quit, accelerator: "⌘Q"),
    ])
}

@Test func lastClickedHeaderComesFirst() {
    let rows = MenuRows.build(accounts: [a], lastClicked: a, appName: "Menu OTP")
    #expect(rows.first == MenuRow(kind: .header, label: "Last clicked: GitHub: jane"))
}

@Test func emptyListOffersFirstAccountButAllHiddenDoesNot() {
    let empty = MenuRows.build(accounts: [], lastClicked: nil, appName: "Menu OTP")
    #expect(empty.first == MenuRow(kind: .item, label: "Add Your First Account...", action: .settings))
    let allHidden = MenuRows.build(accounts: [b], lastClicked: nil, appName: "Menu OTP")
    #expect(allHidden.first?.kind == .separator)
}

@Test func selectionWrapsOverSelectableRowsOnly() {
    let rows = MenuRows.build(accounts: [a, c], lastClicked: a, appName: "Menu OTP")
    // header(0) a(1) c(2) sep(3) settings(4) quit(5)
    var sel = MenuSelection(rows: rows)
    #expect(sel.selectable == [1, 2, 4, 5])
    sel.move(1)
    #expect(sel.active == 1)
    sel.move(-1)
    #expect(sel.active == 5)
    sel.move(1)
    #expect(sel.active == 1)
    sel.move(1); sel.move(1)
    #expect(sel.active == 4)
}

@Test func selectionUpFromNothingStartsAtBottom() {
    var sel = MenuSelection(rows: MenuRows.build(accounts: [a], lastClicked: nil, appName: "X"))
    sel.move(-1)
    #expect(sel.active == sel.selectable.last)
}

@Test func hoverIgnoresNonSelectableRows() {
    var sel = MenuSelection(rows: MenuRows.build(accounts: [a], lastClicked: a, appName: "X"))
    sel.hover(1)
    #expect(sel.active == 1)
    sel.hover(0)
    #expect(sel.active == nil)
    sel.hover(1); sel.hover(nil)
    #expect(sel.active == nil)
}

@Test func toggleGate() {
    var gate = MenuToggleGate()
    let t0 = Date(timeIntervalSince1970: 100)
    #expect(gate.onClick(isVisible: false, now: t0) == .show)
    #expect(gate.onClick(isVisible: true, now: t0) == .hide)
    gate.didHide(at: t0)
    #expect(gate.onClick(isVisible: false, now: t0.addingTimeInterval(0.1)) == .ignore)
    #expect(gate.onClick(isVisible: false, now: t0.addingTimeInterval(0.3)) == .show)
}

@Test func backfillRunsAtMostFourAtATimeAndDeliversEveryResult() async {
    actor Gauge {
        var inFlight = 0, peak = 0
        var seen: [String] = []
        func enter() { inFlight += 1; peak = max(peak, inFlight) }
        func leave(_ id: String) { inFlight -= 1; seen.append(id) }
    }
    let gauge = Gauge()
    let items = (0..<10).map { (AccountIdentity(issuer: "I\($0)", account: "a"), "s\($0)") }
    await IconBackfill.run(items, lookup: { source in
        await gauge.enter()
        try? await Task.sleep(for: .milliseconds(20))
        return source == "s3" ? .found(FaviconResult(icon: "x", domain: "d")) : .notFound
    }, onResult: { identity, _ in
        await gauge.leave(identity.issuer)
    })
    // Never more than 4 at once; more than 1 shows they do overlap
    #expect((2...4).contains(await gauge.peak))
    #expect(await gauge.seen.sorted() == items.map(\.0.issuer).sorted())
}

@Test func needsLookupRespectsTTL() {
    let now = Date(timeIntervalSince1970: 10 * 24 * 3600)
    let fresh = Account(account: "a", secret: "S", issuer: "I", iconCheckedAt: (now.timeIntervalSince1970 - 3600) * 1000)
    let stale = Account(account: "a", secret: "S", issuer: "I", iconCheckedAt: (now.timeIntervalSince1970 - 8 * 24 * 3600) * 1000)
    #expect(IconBackfill.needsLookup(Account(account: "a", secret: "S", issuer: "I"), now: now))
    #expect(!IconBackfill.needsLookup(fresh, now: now))
    #expect(IconBackfill.needsLookup(stale, now: now))
    #expect(!IconBackfill.needsLookup(Account(account: "a", secret: "S", issuer: "I", icon: "🙂"), now: now))
}

@Test func moveAccountsMatchesOnMoveSemantics() {
    var list = ["a", "b", "c", "d"].map { Account(account: $0, secret: "S", issuer: "") }
    list.moveAccounts(fromOffsets: [0], toOffset: 3) // drag "a" to just before "d"
    #expect(list.map(\.account) == ["b", "c", "a", "d"])
    list.moveAccounts(fromOffsets: [3], toOffset: 0)
    #expect(list.map(\.account) == ["d", "b", "c", "a"])
}
