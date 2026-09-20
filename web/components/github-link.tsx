/** The Menu OTP repository. Every page's links and the release badge derive from it. */
export const REPO_URL = 'https://github.com/iambriansreed/menu-otp';

export function GitHubLink() {
    return (
        <a class="github-link" href={REPO_URL} target="_blank" rel="noopener" aria-label="View source on GitHub">
            <img src="github.svg" alt="" width="22" height="22" />
        </a>
    );
}
