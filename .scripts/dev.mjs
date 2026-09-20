#!/usr/bin/env node
/**
 * @file Runs the demo app and the website's dev server together, as `npm run dev`.
 *
 * Both children are started in their **own process groups** (`detached: true`) and are
 * killed by group on the way out. That matters for the app in particular:
 * `app/scripts/demo.sh` is a shell script that builds and then `exec`s the real binary,
 * so a plain `kill` aimed at the pid we know can leave the app running. An orphaned copy
 * then holds the single-instance lock and the next `npm run dev` quits silently.
 *
 * This is what `npm run dev` calls, so it must never call `npm run dev` back.
 *
 * @module dev
 */

import path from 'node:path';
import { spawn } from 'node:child_process';

process.chdir(path.join(import.meta.dirname, '..'));

/**
 * A child started in its own process group.
 *
 * @typedef {object} Child
 * @property {string} name For messages.
 * @property {import('node:child_process').ChildProcess} process The spawned process.
 */

/** @type {Child[]} */
const children = [];

/** Guards against re-entering {@link stopAll} from a child's own exit handler. */
let stopping = false;

/**
 * Signals every child's process group, then exits.
 *
 * Failures are ignored on purpose: by the time we get here a child has usually exited
 * already, and its group no longer exists.
 *
 * @param {number} code Exit code for this process.
 * @returns {never}
 */
function stopAll(code) {
    stopping = true;
    for (const { process: child } of children) {
        if (child.pid === undefined) continue;
        try {
            // Negative pid: the group, not just the leader
            process.kill(-child.pid, 'SIGTERM');
        } catch {
            // already gone
        }
    }
    process.exit(code);
}

/**
 * Starts a command in its own process group, wired to this terminal.
 *
 * `detached: true` is what makes the child a group leader, so {@link stopAll} can signal
 * the whole group. The trade-off is that a detached child does **not** receive the
 * terminal's Ctrl+C, which is why the signal handlers below forward it explicitly.
 *
 * @param {string} name A label for messages.
 * @param {string} command The executable to run.
 * @param {string[]} args Its arguments.
 * @param {string} [cwd] Directory to run in, relative to the repository root.
 * @returns {void}
 */
function start(name, command, args, cwd) {
    const child = spawn(command, args, { cwd, stdio: 'inherit', detached: true });
    child.on('exit', (code, signal) => {
        // The first child to stop takes the session with it, so Ctrl+C in either half,
        // or a crash, ends the whole thing rather than leaving one running unattended.
        if (!stopping) {
            const how = signal ? `signal ${signal}` : `code ${code}`;
            console.error(`\n${name} exited (${how}); stopping.`);
            stopAll(typeof code === 'number' ? code : 1);
        }
    });
    children.push({ name, process: child });
}

for (const signal of /** @type {const} */ (['SIGINT', 'SIGTERM'])) {
    process.on(signal, () => stopAll(signal === 'SIGINT' ? 130 : 143));
}

// The app first: it builds before it runs, so starting it now overlaps that build with
// the dev server coming up.
start('the demo app', 'app/scripts/demo.sh', []);

// Skrapa runs every command from the skrapa root, and this uses the binary that
// package-lock.json pins rather than whatever `npx` would resolve.
start('the dev server', path.resolve('node_modules/.bin/skrapa'), ['dev'], 'web');
