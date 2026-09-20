# Menu OTP

A native macOS menu bar app for TOTP codes. Click the menu bar icon, click an
account, and its current 6-digit code is on the clipboard. It's a Swift/AppKit port
of the Electron app [Easy OTP](https://github.com/iambriansreed/easy-otp) and runs
next to it (its own name, bundle id and data).

- Accounts are stored encrypted (AES-256-GCM) in
  `~/Library/Application Support/Menu OTP/accounts.enc`. The key is kept in your
  login Keychain.
- Add accounts by pasting an `otpauth://` URL, typing them in, or importing a
  `.txt` file with one `otpauth://` URL per line.
- Copied codes are marked concealed/transient, so clipboard managers that honour
  the [nspasteboard.org](http://nspasteboard.org) markers don't keep them.
- Icons are favicons looked up through DuckDuckGo's icon service, falling back to
  Google's. Those services see which issuer domains are looked up; nothing else
  about an account leaves your Mac. You can use an emoji instead.

If the menu bar icon is ever out of reach (hidden behind the notch, say), open the
app again from Finder or Spotlight: that opens Settings.

Requires macOS 14 or later.

## Install

Download the `.dmg`, drag Menu OTP to Applications. The app is ad-hoc signed, not
notarized, so Gatekeeper blocks the first launch: right-click the app and choose
Open, or run

```sh
xattr -dr com.apple.quarantine "/Applications/Menu OTP.app"
```

The first time the app saves or reads its accounts, macOS asks whether it may use
its Keychain item. Choose **Always Allow**. Each new build asks once more, because
an ad-hoc signed build is a new app to the Keychain.

## Build

Needs Swift 6 from Xcode or from the Command Line Tools alone. With Xcode selected,
plain `swift test` works from `app/`; `app/scripts/test.sh` works with either, from
anywhere.

The app is a Swift package in [app/](app/), with its own scripts. Run them from the
repository root:

```sh
app/scripts/test.sh              # unit tests (plain swift test works too, but only from app/)
app/scripts/demo.sh              # build and run with fake accounts from app/scripts/demo-data.txt
app/scripts/demo.sh --self-test  # scripted UI checks; exit status is the result
app/scripts/bundle.sh            # build "app/build/Menu OTP.app" (debug)
app/scripts/make-dmg.sh          # universal release build -> "app/build/Menu OTP-<version>.dmg"
app/scripts/make-icons.sh        # regenerate the icons from app/Resources/icon.png
```

Demo mode never touches your real accounts or the Keychain.

The website is a static [Skrapa](https://skrapa.iambrian.com) site in [web/](web/). It
shares the repository's `package.json` with the release tooling, so `npm install` once
at the root, then:

```sh
npm run dev                     # the demo app and the site's dev server together
npm run build                   # static HTML into web/dist
npm run typecheck               # check the JSDoc types on .scripts/*.mjs
.scripts/version.mjs            # print the version (.scripts/version.mjs 0.2.0 sets it by hand)
.scripts/release.mjs --dry-run  # what the next release would be
```

## Commits and releases

Commit subjects follow [Conventional Commits](https://www.conventionalcommits.org)
(`feat: ...`, `fix(popover): ...`, `docs: ...`), because they decide the next version
and write [CHANGELOG.md](CHANGELOG.md). Turn on the check once per clone:

```sh
git config core.hooksPath .scripts/hooks
```

Pushing to `main` is the release process. GitHub Actions runs the tests and, when the
commits since the last release include a `feat`, `fix`, `perf` or breaking change, bumps
the version, updates the changelog, builds the `.dmg` and publishes it as the GitHub
release `v<version>`; then it deploys the website. Below 1.0.0 a breaking change bumps
the minor version and anything else the patch. A push of only `docs`, `chore`, `ci`,
`test`, `style`, `refactor` or `build` commits releases nothing.

The version lives in one place, `app/Resources/Info.plist` (`CFBundleShortVersionString`);
the app, the `.dmg` name, the release tag and the website all take it from there.

## License

[Apache-2.0](LICENSE). Copyright 2026 Brian Reed. Redistributions and forks must keep
the [NOTICE](NOTICE) file.
