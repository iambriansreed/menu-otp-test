# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Menu OTP is a native macOS (14+) menu bar app, a Swift port of the Electron app
Easy OTP (`/Users/brianreed/Projects/easy-otp`, whose `src/` and `CLAUDE.md` are
the behavioural reference). It stores TOTP accounts encrypted on disk and copies
the current 6-digit code when an account is clicked in its popover. It runs next to
Easy OTP: its own name, bundle id `com.iambrian.menu-otp`, data directory and
Keychain item.

## Repository layout

Two self-contained subprojects, plus the tooling that spans them:

```
app/          the Swift app: Package.swift, Sources/, Tests/, Resources/, scripts/, build/
web/          the website: the Skrapa root (tsconfig.json), pages, assets/, dist/
.scripts/     tooling that touches both: release.mjs, version.mjs, dev.mjs, hooks/
package.json  npm for the website and the release tooling; node_modules/ at the root
.github/      the workflows
```

- `app/scripts/*` are **app-only** shell scripts: they `cd` to `app/` and know nothing
  about npm, Skrapa or the website. Anything spanning both lives in `.scripts/`.
- `.scripts/*.mjs` are ES modules written in JavaScript and typed with JSDoc, not
  TypeScript, so nothing needs compiling before it runs. `npm run typecheck`
  (`.scripts/tsconfig.json`, `checkJs` + `nodenext`, TypeScript 6) keeps the JSDoc
  honest. The package itself stays CommonJS: `"type": "module"` at the root breaks
  Skrapa, which compiles pages to CommonJS under `web/.skrapa` and `require()`s them.
- `.scripts/release.config.json` is plain JSON. The one piece that has to be code, the
  Info.plist updater, is named in it as a module path (`.scripts/plist-version.mjs`)
  that commit-and-tag-version `require()`s: Node 24 can `require()` an ES module, and
  its named exports are exactly the `readVersion`/`writeVersion` pair the tool wants.
- `.scripts/hooks/commit-msg` is a two-line shell shim, because git insists on that
  exact filename; it runs `commit-msg.mjs`, which holds the logic and is therefore
  covered by `npm run typecheck`. That module uses only Node builtins, so the hook still
  works in a clone where `npm install` was never run.
- `.gitignore` hides dotfiles with `.*`, so `.scripts` is re-included with `!.scripts`.
- Every command below is written to run from the repository root.

## Commands

Built with SwiftPM and shell scripts; there is no .xcodeproj and no xcodebuild. Xcode 27
(Swift 6.4) is the selected toolchain, and everything also works with only the Command
Line Tools selected.

```sh
app/scripts/test.sh                      # swift test; adds Testing.framework paths on CLT-only setups
app/scripts/test.sh --filter AccountsModel        # one suite/test by name
MENU_OTP_KEYCHAIN_TESTS=1 app/scripts/test.sh --filter keychain    # real login Keychain, off by default
MENU_OTP_NETWORK_TESTS=1 app/scripts/test.sh --filter liveLookup   # real icon services, off by default
(cd app && swift build)                  # compile everything
app/scripts/demo.sh                      # debug .app in demo mode (fake accounts)
app/scripts/demo.sh --self-test          # scripted UI checks, prints PASS/FAIL, exit status = result
app/scripts/demo.sh --snapshot /tmp/snaps  # screenshots of the menu and Settings
                                         # (--real-icons: fetch real favicons, as for the website)
                                         # (both use their own demo data dir, so they
                                         # run beside an interactive demo copy)
app/scripts/bundle.sh [debug|release]    # "app/build/Menu OTP.app"; release = universal
app/scripts/make-dmg.sh                  # "app/build/Menu OTP-<version>.dmg"
app/scripts/make-icons.sh                # .icns from app/Resources/icon.png, status PNGs
                                         # from app/Resources/glyph.png (see the script)

npm install                              # once, at the root: Skrapa + the release tooling
npm run dev                              # .scripts/dev.mjs: the demo app and the site's dev server
npm run build                            # the site, into web/dist
.scripts/version.mjs                     # print the version
.scripts/version.mjs 0.2.0               # set it everywhere (see "Version" below)
.scripts/version.mjs --check             # exit 1 if a generated copy disagrees; CI runs this
.scripts/release.mjs --dry-run           # what the next release would be (CI cuts the real one)
npm run typecheck                        # check .scripts/*.mjs JSDoc types
git config core.hooksPath .scripts/hooks  # once per clone: Conventional Commit check on commit
```

- `swift build` and `swift test` have to run from `app/`, which holds `Package.swift`.
  The scripts do that themselves.
- With Xcode selected, plain `swift test` works. With only the Command Line Tools
  selected, it fails with "no such module 'Testing'" (Swift Testing ships with the
  CLT but isn't on SwiftPM's search path); `app/scripts/test.sh` works in both cases.
- `app/scripts/bundle.sh release` uses `--arch arm64 --arch x86_64` under Xcode's SwiftPM
  (whose per-triple builds share one output directory) and two `--triple` builds +
  `lipo` under the CLT (which can't do multi-arch). Xcode's build system warns that
  x86_64 is deprecated "for macOS 27.0"; that's harmless, and the binary's `minos` is 14.0.
- `app/scripts/demo.sh` execs the binary inside the bundle directly (not `open`), so
  `MENU_OTP_DEMO_FILE` and the arguments reach it.
- When running the app from an agent, wrap it in a timeout
  (`perl -e 'alarm 240; exec @ARGV' app/scripts/demo.sh --self-test`) and **only ever
  run demo mode**. A real-mode launch touches the Keychain, and the access prompt
  blocks until a human answers it.

## Architecture

Two targets. `OTPCore` (Swift 6 language mode, no AppKit/SwiftUI) holds everything
testable. `MenuOTP` (Swift 5 language mode on purpose, since AppKit callbacks fight
strict Sendable checking) is the UI shell.

| File | Responsibility |
| --- | --- |
| `OTPCore/Base32.swift`, `TOTP.swift` | RFC 4648 base32, RFC 6238 TOTP (SHA-1, 30 s, 6 digits, fixed) |
| `OTPCore/Account.swift`, `AccountList.swift` | `Account` (JSON shape identical to Easy OTP's), identity, upsert/import/icon-apply on `[Account]` |
| `OTPCore/OTPAuthURL.swift` | `otpauth://totp/` parsing with WHATWG-URL-compatible quirks |
| `OTPCore/KeyProvider.swift`, `AccountStore.swift`, `InstanceLock.swift` | Keychain key, encrypted atomic store, one instance per data directory |
| `OTPCore/IssuerDomains.swift`, `IconImage.swift`, `FaviconService.swift`, `FaviconResult.swift` | Favicon lookup: domain guesses, ICO/DIB decoding, DuckDuckGo then Google, caching |
| `OTPCore/MenuLogic.swift`, `IconBackfill.swift` | Menu rows, keyboard selection, click toggle gate, 4-wide lookup runner |
| `OTPCore/AccountsModel.swift`, `IconEditorModel.swift` | `@Observable` state shared by both windows; icon editor state |
| `MenuOTP/Popover/*` | The status-item popover (custom NSPanel + SwiftUI) |
| `MenuOTP/Settings/*` | The Settings window (a ScrollView of sections, not a List) |
| `MenuOTP/AppDelegate.swift` | Startup, instance lock, status item, wiring, demo/test modes |
| `MenuOTP/SelfTest.swift`, `Snapshots.swift` | Demo-only test hooks |

### Invariants (read before changing the popover)

- The popover is a borderless **non-activating `NSPanel`** at `.popUpMenu` level,
  joining all Spaces including full-screen ones. **Never call `NSApp.activate()`
  when showing it**: activation drags the user off a full-screen Space and the focus
  churn dismisses the menu. Settings *does* activate (it's an ordinary window).
- Hover and clicks are handled by `MenuHostingView`'s own `.activeAlways` tracking
  area, hit-testing row frames reported by `MenuView`, because SwiftUI hover/tap
  follow window-active state and this app is never active while the menu is open.
- The displayed hosting view has `sizingOptions = []` (otherwise it collapses the
  panel to 0x0); a separate never-displayed `measuringView` with its own
  `MenuHighlight` supplies `fittingSize`. Content is swapped and measured
  synchronously before the panel is shown, so it never flashes at a stale size.
- Placement: `MenuPanelController.placedFrame(of:)` judges the status item against
  the screen's full frame, not `visibleFrame` (with an auto-hiding menu bar, as in
  every full-screen Space, the visible frame covers the menu bar strip). Until the
  item is placed (just after launch) the menu hangs from the visible frame's top.
- Dismissal: resign-key with a 150 ms grace (transient key loss while a panel
  settles), a global mouse-down monitor for clicks in other apps, a Space change or
  another app activating, Escape. Status item clicks go through `MenuToggleGate`: an
  open menu closes, and a click within 250 ms of a hide is ignored so the click that
  dismissed it can't reopen it. The status item stays highlighted while it's open.
- A refresh while open keeps the highlighted row (matched by its action). Rows are
  their own views (`HighlightedRow`, `ScrollToHighlight`) because the macOS 27 SDK
  doesn't redraw observation reads made inside a `ForEach` closure. Rows carry an
  accessibility action, since VoiceOver can't trigger the raw mouse handling.
- Popover clicks resolve accounts by **identity** (issuer + account), never index.
- After a copy the menu is replaced by a "Copied" confirmation that stays until
  dismissal; model changes don't redraw over it.
- ⌘Q in the popover matches `charactersIgnoringModifiers`, not the key code: key
  codes are ANSI key *positions*, so code 12 is Q here but A on AZERTY. The main
  menu's Quit item handles the real ⌘Q first; the popover's case is the fallback.

### Settings is not a List

On macOS a SwiftUI `List` holds a click on a text field inside one of its rows for
the double-click interval (0.5 s by default) before the field gets focus, which made
every field in Settings feel laggy. It was measured on real clicks: focus 611 ms
after mouse-down in a List, immediate without one. Settings is therefore a
`ScrollView` of `SettingsSection`s. Reordering is a separate mode (the Reorder
button, then Done): only there is the account list a real `List` with `.onMove`, for
its native drag and drop (lifted row, insertion line, edge autoscroll), and that mode
shows no text fields. The self-test asserts both halves. Synthetic clicks don't
reproduce the delay, so test focus changes with a real mouse.

Settings opens with no text field focused (`SettingsWindowController` clears the
first responder AppKit assigns), Edit focuses the Issuer field, and Import's file
picker is a `fileImporter` sheet on the Settings window, accepting any data file.

### Data

- Everything mutates through `AccountsModel.mutate`: copy, change, refuse duplicate
  identities, save, publish, `onChange` (the popover re-measures). A change that
  changes nothing is neither saved nor published. Settings and the popover read the
  same model, so none of Easy OTP's IPC reconciliation exists here.
- Secrets must decode as base32 wherever they enter (URL, manual add, edit,
  import); `ModelError` and the store/Keychain errors are `LocalizedError`s whose
  text is shown to the user as-is. An account name is equally required everywhere,
  import included: issuer alone is an identity that every unnamed account from that
  issuer would share, and the second one would upsert its secret over the first.
- `accounts.enc` = `"MOTP1"` + AES-GCM sealed box of the JSON array, written to a
  temp file then `rename(2)`d, mode 0600. A missing file loads as empty *without*
  touching the Keychain. A key that can't be obtained throws, and the app shows an
  alert and quits rather than risk saving over real data. A file that can't be
  decrypted with a key we do have is renamed to `accounts.enc.unreadable-<epoch>`,
  never deleted, and the user is told; if the rename fails, load throws instead.
- The key is a generic password (service `com.iambrian.menu-otp`, account
  `accounts-encryption-key`) in the login Keychain. Ad-hoc signing means every new
  build prompts once for access.
- Launch backfill: icon-less accounts are looked up 4 at a time. Only
  `FaviconOutcome.notFound` (the services answered) stamps `iconCheckedAt` (epoch
  ms) and suppresses retries for 7 days; `.unreachable` (offline, timeout) stamps
  nothing. Explicit lookups from Settings never stamp. An edit that changes the
  search source drops the stamp. `FaviconService` caches hits for the process
  lifetime and real misses for 10 minutes, never caches unreachable results, and
  shares in-flight lookups.
- Launching the app again while it runs opens Settings: `applicationShouldHandleReopen`
  for Finder/Spotlight/Dock, and a second process that loses the instance lock posts
  a distributed notification (object: the data directory) before quitting. In
  `--self-test`/`--snapshot` a lost lock exits 2 instead, so a test can't pass
  without running.
- Saving an edit panel whose icon editor was never touched keeps the account's
  *current* icon (a backfill may have found one after the panel opened).

### Demo mode and test hooks

`MENU_OTP_DEMO_FILE=<file of otpauth:// URLs>` (set by `app/scripts/demo.sh`): data dir
`$TMPDIR/menu-otp-demo`, in-memory key, a fake login item, own instance lock (runs
beside the real app). `--self-test` and `--snapshot <dir>` are honoured only in demo
mode. Snapshots use `screencapture -l <windowNumber>` on the app's own on-screen
windows. Offscreen rendering (`cacheDisplay`, `ImageRenderer`) misses SwiftUI/AppKit
content.

## The website

A static [Skrapa](https://skrapa.iambrian.com) site (Node.js 24+) in `web/`, ported from
Easy OTP's. npm lives at the repository root, shared with the release tooling:
`npm install` once there, then `npm run dev` (live reload on port 4159) or
`npm run build`. Both `cd web` first, because Skrapa runs every command from the
*skrapa root*, the directory holding the `tsconfig.json` that carries its settings under
a `skrapa` key. `web/` is both that and Skrapa's *project root* (`projectRoot: "."`),
which keeps `skrapa.d.ts` and the output inside `web/` instead of at the repository root.

| Path | |
| --- | --- |
| `web/tsconfig.json` | the skrapa root: TypeScript config plus the `skrapa` settings |
| `web/index.tsx`, `web/development/index.tsx` | the pages; an `index.tsx` exporting `Page()` is a route, so these are `/` and `/development/` |
| `web/assets/` | images and `style.css`, copied to the output verbatim |
| `web/version.json` | generated: the version the download button shows |
| `web/dist/` | build output (gitignored) |
| `web/skrapa.d.ts` | regenerated by every Skrapa command; don't edit it, and don't confuse it with the site's own types |
| `web/.skrapa/` | the compiled pages Skrapa runs to render HTML (gitignored) |

- Pages live directly in `web/`, not in a `web/src/`. Skrapa searches for routes under
  the skrapa root, so a page in `web/src/` would be served at `/src/`.
- `REPO_URL` in `web/components/github-link.tsx` is the one place the GitHub repository
  is named.
- The screenshots in `web/assets/` come from
  `app/scripts/demo.sh --snapshot <dir> --real-icons`; some are crops.
- Pages compile with `tsc --outDir .skrapa --rootDir .` **inside `web/`**, which Skrapa
  hard-codes. A page therefore can't import anything above `web/`, which is why the
  version the site shows is `web/version.json` rather than the root `package.json`.
- `.github/workflows/deploy-web.yml` builds it on Node 24 and deploys `web/dist` to
  GitHub Pages. It has no push trigger of its own: `release.yml` calls it as its last job
  (see "Release pipeline"), and it can be run by hand to redeploy `main`. The site is
  served from the custom domain `menu-otp.iambrian.com` (set in the repo's Pages settings
  along with the "GitHub Actions" source, not by a committed `CNAME`), which is why the
  `skrapa` settings have `base: '/'`. CI needs `package-lock.json` and `web/assets/`
  committed; `web/dist` is gitignored, so it only has what's in `web/`.

## Version

The version is set in one place, `CFBundleShortVersionString` in `app/Resources/Info.plist`,
and **never typed anywhere else**. Releases bump it automatically from the commit
messages (next section); `.scripts/version.mjs <x.y.z>` sets it by hand when that's
really wanted. Everything else derives from it:

- The app reads its own bundle: `AppEnvironment.versionText` ("0.1.0 (57)") feeds the
  footer at the bottom of Settings, and the standard About panel shows the same pair.
- `CFBundleVersion` (the build number) is the git commit count, stamped by
  `app/scripts/bundle.sh` into the *built* bundle's plist only. The source plist's `1` is
  the fallback for a tree with no git history. Nobody bumps it.
- `app/scripts/make-dmg.sh` names the `.dmg` from it, and `release.yml` tags `v<version>`.
- Two generated copies follow it, because `tsc` can import JSON but not a plist:
  `"version"` in the root `package.json` (this repo's npm package), and
  `web/version.json`, which `web/index.tsx` imports to show it on the download button.
  It's a separate file rather than the root `package.json` because Skrapa compiles pages
  with `--rootDir` at `web/`, so a page can't import anything above that directory. It
  needs `resolveJsonModule`, and `version.json` has to be in `web/tsconfig.json`'s
  `include` because the project is `composite`.
- Both writers, `.scripts/release.mjs` and `.scripts/version.mjs`, change every copy
  together (a text substitution for the plist, since PlistBuddy would reformat the
  whole file; `npm version` for `package.json` and the lockfile), and both workflows
  run `.scripts/version.mjs --check` first, so a hand edit that missed one fails CI
  instead of shipping a wrong number.

## Release pipeline

Releasing is "push Conventional Commits to `main`". Nobody picks a version number: the
commit messages do, the same way Skrapa's pipeline works (`commit-and-tag-version`).

`.scripts/release.mjs` is the one definition of a release, run by CI and usable by hand.
From the commits since the last `v*` tag it works out the bump, writes it to the three
version files, adds a section to `CHANGELOG.md`, commits `chore(release): x.y.z` and
tags `v<x.y.z>`. It never pushes. Config (and the Info.plist updater the tool needs) is
`.scripts/release.config.json`, passed with `--config` because a `.versionrc` would be a
gitignored dotfile and there's no root `package.json`; the tool is fetched by `npx`,
pinned in the script.

- **What releases:** a `feat`, `fix`, `perf` or breaking change (`!` after the type, or
  a `BREAKING CHANGE:` footer) since the last tag. Only `docs`, `chore`, `ci`, `test`,
  `style`, `refactor` or `build` commits cut nothing, so a README or website push ships
  no new `.dmg`. `release.sh` decides this itself: the tool's own
  `--noBumpWhenEmptyChanges` ignores `perf`.
- **Tooling:** `commit-and-tag-version` and `skrapa` are the repo's only npm
  dependencies, pinned in `package-lock.json`. `release.sh` runs the local
  `node_modules/.bin` copy, never `npx --yes`: the release job holds a token that can
  push to `main` and builds the app people keep their 2FA secrets in, so nothing there
  resolves a dependency at run time.
- **Bump size:** below 1.0.0 a breaking change bumps the minor version and everything
  else the patch. From 1.0.0 on it's major / minor (`feat`) / patch.
  `.scripts/release.mjs --release-as 1.0.0` chooses the version instead.
- With no `v*` tag yet it passes `--first-release`: the version already in Info.plist is
  tagged as it stands and the changelog starts there.
- `.scripts/hooks/commit-msg` rejects a subject that isn't a Conventional Commit, since
  the pipeline silently leaves those out of the bump and the changelog. It's a plain
  Node script using only builtins (no husky, no commitlint), enabled per clone:
  `git config core.hooksPath .scripts/hooks`. The logic is in `commit-msg.mjs` so
  `npm run typecheck` covers it; the extensionless `commit-msg` beside it is a committed
  symlink to it, because that is the filename git insists on.

`.github/workflows/release.yml` is the only workflow that runs on a push to `main`:

1. A `workflow_dispatch` with no `tag` would otherwise release from whichever branch it
   was started on and then push that branch to `main` in step 5, so the run refuses any
   branch but `main` first. With a `tag` it only builds and publishes, so any ref is fine.
2. On a macOS runner: check out the branch with full history and tags, select the
   newest installed Xcode (the app is developed against the newest toolchain, rarely the
   image default), `.scripts/version.mjs --check`, `app/scripts/test.sh`.
3. `.scripts/release.mjs` cuts the release locally, if the commits call for one.
4. "A release" is then simply a `v*` tag on HEAD, however it got there (cut just now,
   pushed from a laptop, or named by `workflow_dispatch`'s `tag` input), and it needs
   publishing when GitHub has no release for that tag. That makes a re-run finish a
   release whose build or upload failed.
5. Only if so: `app/scripts/make-dmg.sh`, **then** `git push --follow-tags` (so a failed
   build leaves no release commit on `main`), then `gh release create` with the `.dmg`
   and that version's `CHANGELOG.md` section (`.scripts/release.mjs --notes <version>`).
6. The `deploy` job calls `deploy-web.yml` with the release tag, or with the pushed
   commit when nothing was released, so the site always shows a published version.

- The release commit is itself a push to `main`. GitHub doesn't start workflows from
  pushes made with `GITHUB_TOKEN`; if that ever changes (a PAT), the rerun finds HEAD
  tagged and already published and only redeploys the site.
- The build is the same as a local one: universal, ad-hoc signed, not notarized, no
  secrets or certificates. `--self-test` and `--snapshot` are not run in CI.
- `fetch-depth: 0` matters twice: the changelog is written from the commits since the
  last tag, and the build number is the commit count (a shallow clone counts 1).
- GitHub stores the asset with the space replaced: `Menu.OTP-<version>.dmg`. The
  website links to `/releases/latest`, not to the file, so nothing depends on the name.

## Rules

- Never read or commit `local-otp*` files; assume they hold real secrets.
- Commit subjects are Conventional Commits (`feat:`, `fix(popover):`, `docs:` ...): they
  choose the next version and write the changelog. Never edit `CHANGELOG.md` or bump
  the version by hand as part of a change.
- No `Co-Authored-By` or other Claude attribution in commit messages or PRs.
- Keep `app/` free of npm, Skrapa and website references, and `web/` free of Swift ones.
  Anything that genuinely spans both belongs in the root `.scripts/`.
- Four-space indentation, ~100-column lines, and "why" comments on anything
  non-obvious, especially window/focus behaviour. Those comments are load-bearing.
