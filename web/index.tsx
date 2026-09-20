import { GitHubLink, REPO_URL } from './components/github-link';
// The app's version: a generated copy of CFBundleShortVersionString in
// app/Resources/Info.plist, kept in step by .scripts/version.mjs and checked by CI before
// every deploy, so it's never typed here. The badges beside it show GitHub's latest
// release, which trails this by the few minutes a release build takes.
import { version } from './version.json';

const RELEASE_URL = `${REPO_URL}/releases/latest`;
const BUILD_COMMAND = `git clone ${REPO_URL}.git && cd menu-otp && app/scripts/make-dmg.sh`;

export function Page(): Skrapa.Page {
    return (
        <>
            <header class="nav">
                <a href="./" class="brand">
                    <img src="logo.png" alt="" width="28" height="28" />
                    Menu OTP
                </a>
                <nav>
                    <a href="development/">Development</a>
                    <GitHubLink />
                </nav>
            </header>

            <section class="hero">
                <div class="logo" role="img" aria-label="Menu OTP logo"></div>
                <h1>Menu OTP</h1>
                <p class="tagline">
                    Two-factor codes in your Mac's menu bar, in a small native app. Click an account
                    and its current code is copied to the clipboard.
                </p>
                <div class="cta-row">
                    <a class="btn btn-primary" href={RELEASE_URL}>
                        Download for macOS
                    </a>
                    <a class="btn btn-secondary" href="#download">
                        Install instructions
                    </a>
                </div>
                <img
                    class="badge"
                    src="https://img.shields.io/github/v/release/iambriansreed/menu-otp?label=latest"
                    alt="Latest release"
                    width="105"
                    height="20"
                />
                <img
                    class="screenshot screenshot-hero"
                    src="screenshot-menu.png"
                    alt="The Menu OTP menu listing accounts with their service icons, with GitHub highlighted"
                    width="353"
                    height="407"
                />
            </section>

            <section class="download" id="download">
                <h2>Download and install</h2>
                <p class="lede">Requires macOS 14 or later, on Apple silicon or Intel.</p>
                <div class="cta-row">
                    <a class="btn btn-primary" href={RELEASE_URL}>
                        Download Menu OTP {version}
                    </a>
                    <img
                        class="badge"
                        src="https://img.shields.io/github/v/release/iambriansreed/menu-otp?label=latest"
                        alt="Latest release"
                        width="105"
                        height="20"
                    />
                </div>
                <div class="prose">
                    <ol>
                        <li>
                            Open the downloaded <code>.dmg</code> and drag Menu OTP into Applications.
                        </li>
                        <li>
                            The app isn't notarized by Apple, so macOS blocks it the first time. Try
                            these approaches:
                            <ul>
                                <li>
                                    <strong>Right-click method:</strong> In Applications, right-click Menu
                                    OTP, choose <strong>Open</strong>, then click <strong>Open</strong> in
                                    the dialog.
                                </li>
                                <li>
                                    <strong>Terminal method (macOS 15+):</strong> Run this and open the app
                                    again:
                                    <div class="code-block">
                                        <pre>
                                            <code>xattr -dr com.apple.quarantine "/Applications/Menu OTP.app"</code>
                                        </pre>
                                        <button class="copy-btn" type="button">
                                            Copy
                                        </button>
                                    </div>
                                </li>
                                <li>
                                    <strong>Settings method:</strong> Check System Settings → Privacy &
                                    Security for a message about Menu OTP and click{' '}
                                    <strong>Open Anyway</strong>.
                                </li>
                            </ul>
                        </li>
                        <li>
                            Click the Menu OTP icon in the menu bar and choose{' '}
                            <strong>Menu OTP Settings...</strong> to add your first account.
                        </li>
                        <li>
                            The first time Menu OTP saves your accounts, macOS asks whether it may use
                            its Keychain item. Choose <strong>Always Allow</strong>. Each new version asks
                            once more.
                        </li>
                    </ol>
                </div>
            </section>

            <section class="build-locally">
                <h2>Build from source</h2>
                <p class="lede">Requires macOS 14 and Xcode, or just the Command Line Tools, with Swift 6.</p>
                <div class="code-block">
                    <pre>
                        <code>{BUILD_COMMAND}</code>
                    </pre>
                    <button class="copy-btn" type="button">
                        Copy
                    </button>
                </div>
                <p class="sub">
                    The installer is written to <code>menu-otp/app/build/Menu OTP-&lt;version&gt;.dmg</code>
                    . The <a href="development/">development guide</a> covers the other scripts.
                </p>
            </section>

            <section class="usage" id="guide">
                <h2>Using Menu OTP</h2>
                <div class="usage-layout">
                    <div class="prose">
                        <h3>Adding accounts</h3>
                        <p>
                            Click the Menu OTP icon in the menu bar and choose{' '}
                            <strong>Menu OTP Settings...</strong>. The <strong>Add Account</strong>{' '}
                            section has three tabs:
                        </p>
                        <ul>
                            <li>
                                <strong>From URL</strong>: paste an <code>otpauth://totp/</code> URL,
                                like the one encoded in a setup QR code.
                            </li>
                            <li>
                                <strong>Manual</strong>: enter the issuer, account name, and secret,
                                and optionally choose a favicon or an emoji.
                            </li>
                            <li>
                                <strong>Import File</strong>: click or drop a file with one{' '}
                                <code>otpauth://</code> URL per line. Menu OTP reports how many accounts
                                were added, updated, and skipped.
                            </li>
                        </ul>
                        <p>
                            Accounts are matched by issuer and account name, so adding one you already
                            have updates it instead of creating a copy. Imports keep any icon you
                            already chose. A secret that isn't valid base32 is refused when you enter
                            it, rather than failing later when you copy a code.
                        </p>

                        <h3>Copying a code</h3>
                        <p>
                            Click an account in the menu. Its code is copied to the clipboard, and the
                            menu shows the issuer and code in large type until you click somewhere
                            else. For the next minute, the top of the menu shows which account you
                            copied last. Codes are marked as sensitive on the clipboard, so clipboard
                            managers that honor that don't keep them.
                        </p>
                        <img
                            class="screenshot"
                            src="screenshot-copied.png"
                            alt="The copy confirmation showing Stripe, the word Copied, and a six-digit code"
                            width="310"
                            height="57"
                            loading="lazy"
                            decoding="async"
                        />
                        <p>
                            With the menu open, <kbd>Up Arrow</kbd> and <kbd>Down Arrow</kbd> move the
                            highlight, <kbd>Return</kbd> or <kbd>Space</kbd> copies, and <kbd>Esc</kbd>{' '}
                            closes it. <kbd>Command-Q</kbd> quits, or use the <strong>Quit Menu OTP</strong>{' '}
                            item at the bottom of the menu.
                        </p>

                        <h3>Icons</h3>
                        <p>
                            If you add an account without choosing an icon, Menu OTP guesses the
                            service's website from what you entered and fetches its icon. Any account still
                            missing an icon is filled in the next time the app starts, or right away
                            with <strong>Find Missing Icons</strong>, which appears in Settings whenever
                            an account has no icon.
                        </p>
                        <p>
                            To fix a wrong or missing icon, click <strong>Edit</strong> on the account.
                            With <strong>Favicon</strong> selected, type the service's website and the
                            icon is looked up as you type. Choose <strong>Emoji</strong> to open the
                            macOS emoji picker instead.
                        </p>
                        <img
                            class="screenshot"
                            src="screenshot-edit.png"
                            alt="An account open for editing, with its issuer, account name, secret, and favicon website fields"
                            width="428"
                            height="141"
                            loading="lazy"
                            decoding="async"
                        />
                        <p>
                            In the menu, icons stay grey until you point at an account, then show in
                            full color.
                        </p>

                        <h3>Organizing</h3>
                        <p>
                            Click <strong>Reorder</strong> above your accounts, drag them into the order
                            you want the menu to show them, then click <strong>Done</strong>. The eye
                            button hides an account from the menu; it stays in Settings marked{' '}
                            <strong>Hidden</strong>. <strong>Edit</strong> changes an account's details
                            and <strong>×</strong> deletes it, after asking.
                        </p>
                        <img
                            class="screenshot"
                            src="screenshot-reorder.png"
                            alt="Settings in reorder mode: accounts with drag handles and a Done button"
                            width="480"
                            height="320"
                            loading="lazy"
                            decoding="async"
                        />

                        <h3>Getting around</h3>
                        <p>
                            Turn on <strong>Open at login</strong> under <strong>General</strong> in
                            Settings to start Menu OTP with your Mac. It lives in the menu bar and only
                            appears in the Dock while Settings is open. If its menu bar icon is ever out
                            of reach, hidden behind the notch for example, open Menu OTP again from
                            Finder or Spotlight to bring up Settings.
                        </p>

                        <h3>Privacy</h3>
                        <p>
                            Accounts are saved to one file on your Mac, encrypted with AES-256. The key
                            is kept in your login Keychain. The only network requests Menu OTP makes are
                            icon lookups, which send a website name to DuckDuckGo's icon service, and to
                            Google's only when DuckDuckGo has no icon for it. Secrets are never sent
                            anywhere.
                        </p>

                        <h3>Supported codes</h3>
                        <p>
                            Menu OTP generates standard TOTP codes: 6 digits, a new code every 30
                            seconds, using SHA-1. Accounts set up for 8 digits, a different interval,
                            another algorithm, or counter-based (HOTP) codes won't work.
                        </p>

                        <h3>Coming from Easy OTP</h3>
                        <p>
                            Menu OTP is the native rewrite of{' '}
                            <a href="https://easy-otp.iambrian.com">Easy OTP</a>. The two are separate
                            apps with their own data and can run side by side. To bring accounts over,
                            import a file of their <code>otpauth://</code> URLs.
                        </p>
                    </div>
                    <img
                        class="screenshot"
                        src="screenshot-settings.png"
                        alt="The Menu OTP Settings window listing accounts with icons, one marked Hidden, above the Add Account form"
                        width="480"
                        height="583"
                        loading="lazy"
                        decoding="async"
                    />
                </div>
            </section>

            <footer>
                <p>
                    <a href={REPO_URL} target="_blank" rel="noopener">
                        GitHub
                    </a>{' '}
                    · Built with{' '}
                    <a href="https://skrapa.iambrian.com" target="_blank" rel="noopener">
                        Skrapa
                    </a>
                </p>
            </footer>
        </>
    );
}
