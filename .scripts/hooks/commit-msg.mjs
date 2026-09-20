#!/usr/bin/env node
/**
 * @file Git `commit-msg` hook: rejects a commit whose subject is not a Conventional
 * Commit.
 *
 * The release pipeline reads these subjects to choose the version bump and to write
 * `CHANGELOG.md` (see `.scripts/release.mjs`), and a subject it cannot parse is silently
 * left out of both — the commit lands, and the release it should have produced never
 * happens. Catching it here is the difference between a message you can still edit and
 * a gap in the changelog.
 *
 * Enable once per clone:
 * ```sh
 * git config core.hooksPath .scripts/hooks
 * ```
 *
 * Git insists on a hook named exactly `commit-msg`, with no extension, so the file
 * beside this one is a two-line shell shim that runs this module. Keeping the logic in
 * a `.mjs` file is what puts it under `npm run typecheck` with the rest of `.scripts`.
 *
 * It uses nothing but Node builtins: no husky, no commitlint, and nothing from
 * `node_modules`, so it keeps working in a clone where `npm install` was never run.
 *
 * @module hooks/commit-msg
 */

import fs from 'node:fs';

/**
 * The types the changelog understands. The first three (plus anything marked breaking
 * with `!`) produce a release; the rest are recorded but ship nothing.
 *
 * @type {readonly string[]}
 */
const TYPES = [
    'feat',
    'fix',
    'perf',
    'revert',
    'docs',
    'style',
    'refactor',
    'test',
    'build',
    'ci',
    'chore',
];

/**
 * A valid subject: a known type, an optional `(scope)` with no nested parentheses, an
 * optional `!` for a breaking change, then `": "` and a description that actually starts
 * with a non-space character.
 *
 * @type {RegExp}
 */
const CONVENTIONAL = new RegExp(`^(?:${TYPES.join('|')})(?:\\([^()]+\\))?!?: [^ ]`);

/**
 * Subjects git writes itself, plus the autosquash markers that a later
 * `git rebase --autosquash` folds away. Rejecting these would block ordinary merges and
 * fixups for messages that never reach the changelog.
 *
 * @type {readonly string[]}
 */
const ALLOWED_PREFIXES = ['Merge ', 'Revert "', 'fixup! ', 'squash! ', 'amend! '];

/**
 * Pulls the subject line out of a commit message file: the first line that is neither
 * blank nor one of the `#` comments git appends.
 *
 * @param {string} message The full contents of the commit message file.
 * @returns {string} The subject, or `""` for an empty message.
 */
function subjectOf(message) {
    for (const line of message.split('\n')) {
        if (line.startsWith('#')) continue;
        if (line.trim() === '') continue;
        return line;
    }
    return '';
}

/**
 * Whether a subject may be committed.
 *
 * @param {string} subject The commit's subject line.
 * @returns {boolean} True when it is conventional, or one of git's own.
 */
function isAcceptable(subject) {
    if (ALLOWED_PREFIXES.some((prefix) => subject.startsWith(prefix))) return true;
    return CONVENTIONAL.test(subject);
}

/**
 * Explains the format, with examples labelled by what each one does to a release, since
 * that is the part that is easy to get wrong.
 *
 * @param {string} subject The subject that was rejected.
 * @param {string} file Where the message still is, so the author can recover it.
 * @returns {string}
 */
function help(subject, file) {
    return [
        `Not a Conventional Commit: "${subject}"`,
        '',
        '  <type>(<optional scope>)<optional !>: <description>',
        '',
        '  feat: search accounts by typing         released, under Features',
        '  fix(popover): close on a Space change   released, under Bug Fixes',
        '  perf: cache decoded favicons            released, under Performance',
        '  feat!: new accounts.enc format          released, as a breaking change',
        '  docs: / chore: / ci: / test: / build: / style: / refactor:   no release',
        '',
        `Your message is still in ${file}`,
    ].join('\n');
}

/**
 * @param {string[]} argv Arguments after the script name; git passes one, the path to
 *   the commit message file.
 * @returns {number} 0 to let the commit through, non-zero to reject it.
 */
function main(argv) {
    const [file] = argv;
    if (!file) {
        console.error('usage: commit-msg <path to the commit message>');
        return 2;
    }
    /** @type {string} */
    let message;
    try {
        message = fs.readFileSync(file, 'utf8');
    } catch (error) {
        console.error(`${file}: ${error instanceof Error ? error.message : String(error)}`);
        return 1;
    }
    const subject = subjectOf(message);
    if (isAcceptable(subject)) return 0;
    console.error(help(subject, file));
    return 1;
}

process.exit(main(process.argv.slice(2)));
