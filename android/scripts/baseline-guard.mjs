import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve, relative, join } from 'node:path';
import { pathToFileURL } from 'node:url';

const sha = data => createHash('sha256').update(data).digest('hex');
export function inspect(root, base, approvalCommit, before) {
  const git = (...args) => execFileSync('git', ['-C', root, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  git('rev-parse', '--verify', `${base}^{commit}`);
  const paths = ['android/screenshot-baselines', 'android/design-assets/baseline-approvals.json'];
  const names = (...args) => git(...args, '--', ...paths).split('\0').filter(Boolean).sort();
  const changes = {
    committed: names('diff', '--name-only', '-z', base, 'HEAD'),
    staged: names('diff', '--cached', '--name-only', '-z'),
    unstaged: names('diff', '--name-only', '-z'),
    untracked: names('ls-files', '--others', '-z'),
  };
  const manifest = {};
  function walk(dir) {
    if (!existsSync(dir)) return;
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const file = join(dir, e.name);
      if (e.isDirectory()) walk(file);
      else { if (!e.isFile()) throw Error(`Non-regular baseline entry: ${file}`); manifest[relative(root, file)] = sha(readFileSync(file)); }
    }
  }
  walk(join(root, paths[0]));
  if (existsSync(join(root, paths[1]))) manifest[paths[1]] = sha(readFileSync(join(root, paths[1])));
  const changed = [...new Set(Object.values(changes).flat())];
  // The caller supplies a trusted approval commit separately from the comparison
  // base. An approval may reference an earlier baseline commit, never itself.
  let approval = null, approvalText = null, trusted = false;
  if (approvalCommit) {
    approvalText = git('show', `${approvalCommit}:android/design-assets/baseline-approvals.json`);
    approval = JSON.parse(approvalText);
    git('merge-base', '--is-ancestor', base, approvalCommit);
    git('merge-base', '--is-ancestor', approval.approvedCommit, approvalCommit);
    git('merge-base', '--is-ancestor', approval.approvedCommit, 'HEAD');
    trusted = approval.baseCommit === git('rev-parse', base) &&
      names('diff', '--name-only', '-z', approval.approvedCommit, 'HEAD').every(p => p === paths[1]);
  }
  const unapproved = changed.filter(path => {
    if (!trusted) return true;
    if (path === paths[1]) return !existsSync(join(root, path)) || readFileSync(join(root, path), 'utf8').trim() !== approvalText;
    return approval.files?.[path] !== (manifest[path] ?? 'DELETED');
  });
  const digest = sha(JSON.stringify(Object.entries(manifest).sort()));
  const stable = !before || before.digest === digest;
  return { baseCommit: git('rev-parse', base), head: git('rev-parse', 'HEAD'), changes, manifest, digest, stable, unapproved,
    status: unapproved.length || !stable ? 'BASELINE_CHANGED' : 'PASS' };
}
if (import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [root, base, approvalCommit, beforePath] = process.argv.slice(2);
  if (!root || !base) throw Error('usage: baseline-guard.mjs <repo> <approved-base-commit> [trusted-approval-commit] [before-json]');
  const report = inspect(resolve(root), base, approvalCommit === "-" ? undefined : approvalCommit, beforePath ? JSON.parse(readFileSync(beforePath)) : null);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  process.exitCode = report.status === 'PASS' ? 0 : 1;
}
