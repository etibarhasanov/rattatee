#!/usr/bin/env node
/**
 * Rattatee — a query to the site's database goes through the site's gate.
 *
 * This app has no database of its own, but the Cloudflare tool a session here
 * holds reaches the site's, production included: the connector is the
 * account's, not the repository's. The site keeps a PreToolUse hook,
 * `.claude/hooks/d1-write-gate.mjs` in etibarhasanov/tallinntastebuds, that
 * makes every write ask and prices every read before it runs, asking about
 * one past 2,000 rows. It ran only in sessions on that repository, so a
 * session here could read a million rows without a prompt — which matters
 * because past five million in a UTC day every read on the account fails,
 * for the website, the map app and every copy of this one.
 *
 * So this hook runs the site's gate, unchanged, where a checkout of the site
 * sits beside this one (`../tallinntastebuds`, as a session holding both
 * repositories has it), from that checkout's root — the gate prices a read
 * against that checkout's db/schema.sql and names the database out of its
 * wrangler.toml. Its answer is handed back as it is. Run with `--after`, it
 * runs the gate's meter the same way, which keeps the day's hand-run reads.
 *
 * Without the site beside it there is nothing to price with, so every query
 * asks, saying why. Fail closed: a wrong ask is one keystroke, a wrong allow
 * is the account's reads for the day. Copying the gate in here instead would
 * be a second copy to fall behind the first, and its table sizes with it.
 */
import { existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const AFTER = process.argv.includes('--after');
const here = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const site = resolve(here, '../tallinntastebuds');
const gate = `${site}/.claude/hooks/d1-write-gate.mjs`;

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => { raw += chunk; });
process.stdin.on('end', () => {
  if (!existsSync(gate)) {
    if (AFTER) return;
    return ask('The site\'s D1 gate is not beside this checkout (../tallinntastebuds), so this query cannot be priced and is asking instead. Add etibarhasanov/tallinntastebuds to the session to have reads priced.');
  }
  /* The gate reads its root from the call's cwd: point it at the site. */
  let input = raw;
  try {
    const call = JSON.parse(raw);
    call.cwd = site;
    delete call.project_dir;
    input = JSON.stringify(call);
  } catch (e) {
    /* Unreadable: the gate says so itself, and asks. */
  }
  const run = spawnSync(process.execPath, AFTER ? [gate, '--after'] : [gate], {
    cwd: site, input, encoding: 'utf8', timeout: 9000
  });
  if (run.status === 0 && run.stdout) return process.stdout.write(run.stdout);
  if (AFTER) return;
  ask('The site\'s D1 gate did not answer (' + (run.error ? run.error.message : 'exit ' + run.status) + '), so this query is asking rather than running unpriced.');
});

function ask(reason) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'ask', permissionDecisionReason: reason }
  }));
}
