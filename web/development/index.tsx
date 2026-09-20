import { GitHubLink, REPO_URL } from '../components/github-link';

const SETUP_COMMAND = `git clone ${REPO_URL}.git && cd menu-otp`;

/** A shell command with a Copy button (see copy.ts). */
function Command({ children }: Skrapa.PropsWithChildren) {
    return (
        <div class="code-block">
            <pre>
                <code>{children}</code>
            </pre>
            <button class="copy-btn" type="button">
                Copy
            </button>
        </div>
    );
}

export function Page(): Skrapa.Page {
    return (
        <>
            <header class="nav">
                <a href="./" class="brand">
                    <img src="logo.png" alt="" width="28" height="28" />
                    Menu OTP
                </a>
                <nav>
                    <a href="./">Home</a>
                    <GitHubLink />
                </nav>
            </header>

            <div class="center">
                <h1>Development</h1>
                <div class="prose">
                    <h2>Prerequisites</h2>
                    <ul>
                        <li>macOS 14 or later. The app is AppKit and SwiftUI and runs nowhere else.</li>
                        <li>
                            Xcode, or just the Command Line Tools, with Swift 6 or later. The project is a
                            Swift package built by scripts; there is no Xcode project.
                        </li>
                        <li>Node.js 24 or later, only if you also want to run this website locally.</li>
                    </ul>

                    <h2>Setup</h2>
                    <Command>{SETUP_COMMAND}</Command>
                    <p>
                        The repository holds two subprojects: the Swift app in <code>app/</code> and this
                        website in <code>web/</code>. There's nothing to install to build the app, which
                        has no third-party dependencies; the app icon and menu bar icons in{' '}
                        <code>app/Resources/</code> are committed, so a fresh clone builds straight away.
                        The website and the release tooling share one <code>package.json</code> at the
                        repository root, so run <code>npm install</code> there before working on either.
                        Every command below is written to run from the repository root.
                    </p>

                    <h2>Running the app</h2>
                    <Command>app/scripts/demo.sh</Command>
                    <p>
                        Builds a debug copy and runs it with the sample accounts in{' '}
                        <code>app/scripts/demo-data.txt</code>. A demo run keeps its data in a temporary
                        folder with a throwaway key, so it never reads or changes your real accounts or
                        touches the Keychain, and it can run alongside the installed app. To load a
                        different file, run{' '}
                        <code>MENU_OTP_DEMO_FILE=path/to/urls.txt app/scripts/demo.sh</code>.
                    </p>
                    <Command>{'app/scripts/bundle.sh release && open "app/build/Menu OTP.app"'}</Command>
                    <p>
                        Builds and opens the real, optimized app with your real accounts. The first time
                        it saves them, macOS asks whether it may use its Keychain item; choose{' '}
                        <strong>Always Allow</strong>. Every rebuild asks once more, because each build
                        is ad-hoc signed and so counts as a new app to the Keychain.
                    </p>
                    <p>
                        Only one copy runs per data folder. Launching another asks the running copy to
                        open Settings and then quits.
                    </p>

                    <h2>Testing</h2>
                    <Command>app/scripts/test.sh</Command>
                    <p>
                        Runs the unit tests for <code>OTPCore</code>, the part of the app with no user
                        interface. With Xcode selected, plain <code>swift test</code> works too; the
                        script also works when only the Command Line Tools are installed. Two groups of
                        tests are off by default: set <code>MENU_OTP_KEYCHAIN_TESTS=1</code> to use the
                        real login Keychain, or <code>MENU_OTP_NETWORK_TESTS=1</code> to ask the real icon
                        services.
                    </p>
                    <Command>app/scripts/demo.sh --self-test</Command>
                    <p>
                        Drives the real menu and Settings window in demo mode, prints a PASS or FAIL line
                        for each check, and exits with the result. Menus and windows flash on screen
                        while it runs, and a click elsewhere can close the menu mid-check, so leave the
                        Mac alone for the few seconds it takes.
                    </p>
                    <Command>app/scripts/demo.sh --snapshot /tmp/snaps --real-icons</Command>
                    <p>
                        Saves screenshots of the menu and Settings in several states. Without{' '}
                        <code>--real-icons</code> a few accounts get placeholder icons; with it they get
                        the services' real favicons, as on this site.
                    </p>

                    <h2>Building</h2>
                    <Command>app/scripts/make-dmg.sh</Command>
                    <p>
                        Builds a universal (Apple silicon and Intel) release and packages it as{' '}
                        <code>app/build/Menu OTP-&lt;version&gt;.dmg</code>. The app is ad-hoc signed and not
                        notarized, so a downloaded copy needs the first-launch steps on the home page.
                    </p>
                    <Command>app/scripts/make-icons.sh</Command>
                    <p>
                        Regenerates <code>app/Resources/AppIcon.icns</code> and the menu bar icons from{' '}
                        <code>app/Resources/icon.png</code>. To use a different icon, replace that 1024-pixel
                        PNG and run it again.
                    </p>

                    <h2>Commits and releasing</h2>
                    <Command>git config core.hooksPath .scripts/hooks</Command>
                    <p>
                        Commit subjects follow{' '}
                        <a href="https://www.conventionalcommits.org" target="_blank" rel="noopener">
                            Conventional Commits
                        </a>{' '}
                        (<code>feat: ...</code>, <code>fix(popover): ...</code>, <code>docs: ...</code>),
                        because they choose the next version and write <code>CHANGELOG.md</code>. That
                        command, run once per clone, turns on a hook that rejects a subject in any other
                        form.
                    </p>
                    <p>
                        Pushing to <code>main</code> is the release process; nobody picks a version
                        number. A GitHub Actions workflow runs the tests and, when the commits since the
                        last release include a <code>feat</code>, <code>fix</code>, <code>perf</code> or
                        breaking change, bumps the version, adds the release to the changelog, builds the{' '}
                        <code>.dmg</code> with <code>app/scripts/make-dmg.sh</code> and publishes it as a
                        GitHub release. Then it deploys this site. Below 1.0.0 a breaking change bumps
                        the minor version and anything else the patch. A push of only docs, chores or
                        refactors releases nothing.
                    </p>
                    <Command>.scripts/release.mjs --dry-run</Command>
                    <p>
                        Shows what the next release would be. The version itself lives in one place,{' '}
                        <code>CFBundleShortVersionString</code> in <code>app/Resources/Info.plist</code>: the
                        app's Settings and About panel, the <code>.dmg</code> name and the release tag
                        read it from there, and a release also updates the generated copy in{' '}
                        <code>web/version.json</code> that this site shows. The build number is the git
                        commit count, stamped in at build time.
                    </p>

                    <h2>How it works</h2>

                    <h3>Two parts</h3>
                    <p>
                        <code>OTPCore</code> holds everything that can be tested without a screen: codes,
                        parsing, encrypted storage, icon lookup, and the account model the menu and
                        Settings share. <code>MenuOTP</code> is the app around it: the menu bar icon, the
                        menu, and the Settings window.
                    </p>

                    <h3>Storage</h3>
                    <p>
                        Accounts are saved as <code>accounts.enc</code> in{' '}
                        <code>~/Library/Application Support/Menu OTP/</code>, encrypted with AES-256-GCM.
                        The key is a random value kept in the login Keychain. Each save writes a new file
                        and swaps it in, so a crash can't leave a half-written one. A file that can't be
                        decrypted is moved aside, never deleted, and the app says so.
                    </p>

                    <h3>Codes</h3>
                    <p>
                        <code>app/Sources/OTPCore/TOTP.swift</code> generates RFC 6238 codes with 6 digits, a
                        30-second step, and HMAC-SHA1. The <code>algorithm</code>, <code>digits</code>, and{' '}
                        <code>period</code> parameters of an <code>otpauth://</code> URL are ignored.
                        Secrets are checked as base32 when they're entered.
                    </p>

                    <h3>Icons</h3>
                    <p>
                        <code>app/Sources/OTPCore/IssuerDomains.swift</code> turns an issuer name into
                        likely domains, and <code>FaviconService.swift</code> asks DuckDuckGo's icon
                        service for each one, then Google's if DuckDuckGo had nothing. macOS can read <code>.ico</code> files itself but drops
                        their transparency, so <code>IconImage.swift</code> includes its own ICO decoder.
                        Icons are stored with the account as 32x32 PNGs. At launch, accounts without an
                        icon are looked up four at a time; when a service answers that it has none, that's
                        remembered for a week, but a failed lookup (offline, say) is simply tried again
                        next launch.
                    </p>

                    <h3>The menu</h3>
                    <p>
                        The menu bar dropdown is a borderless panel window drawn with SwiftUI, not a
                        native menu. A native menu can't show grey icons that take on color when
                        highlighted, or use custom row spacing. The panel never activates the app, so
                        opening it over a full-screen app doesn't switch Spaces. The comments in{' '}
                        <code>app/Sources/MenuOTP/Popover/</code> explain the focus and placement handling,
                        and are worth reading before changing it.
                    </p>

                    <h3>Settings</h3>
                    <p>
                        Settings is deliberately not a SwiftUI <code>List</code>: on macOS a List holds a
                        click on a text field in one of its rows for the double-click interval (half a
                        second) before the field takes focus. Only Reorder mode, which has no text
                        fields, uses a List, for its native drag and drop.
                    </p>

                    <h2>Scripts</h2>
                    <table>
                        <thead>
                            <tr>
                                <th>Script</th>
                                <th>Description</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr>
                                <td>
                                    <code>app/scripts/demo.sh</code>
                                </td>
                                <td>Run a debug copy with the sample accounts in app/scripts/demo-data.txt</td>
                            </tr>
                            <tr>
                                <td>
                                    <code>app/scripts/demo.sh --self-test</code>
                                </td>
                                <td>Check the real menu and Settings window, then exit with the result</td>
                            </tr>
                            <tr>
                                <td>
                                    <code>app/scripts/demo.sh --snapshot &lt;dir&gt;</code>
                                </td>
                                <td>Save screenshots of the menu and Settings</td>
                            </tr>
                            <tr>
                                <td>
                                    <code>app/scripts/test.sh</code>
                                </td>
                                <td>Run the unit tests</td>
                            </tr>
                            <tr>
                                <td>
                                    <code>app/scripts/bundle.sh [debug|release]</code>
                                </td>
                                <td>Build app/build/Menu OTP.app; release is optimized and universal</td>
                            </tr>
                            <tr>
                                <td>
                                    <code>app/scripts/make-dmg.sh</code>
                                </td>
                                <td>Build a distributable .dmg</td>
                            </tr>
                            <tr>
                                <td>
                                    <code>app/scripts/make-icons.sh</code>
                                </td>
                                <td>Regenerate the app and menu bar icons from app/Resources/icon.png</td>
                            </tr>
                            <tr>
                                <td>
                                    <code>npm run dev</code>
                                </td>
                                <td>Run the demo app and this site's dev server together</td>
                            </tr>
                            <tr>
                                <td>
                                    <code>npm run build</code>
                                </td>
                                <td>Build this site into web/dist</td>
                            </tr>
                            <tr>
                                <td>
                                    <code>.scripts/release.mjs --dry-run</code>
                                </td>
                                <td>Show what the next release would be</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
                <p class="sub">
                    <a class="back" href="./">
                        Back to home
                    </a>
                </p>
            </div>
        </>
    );
}
