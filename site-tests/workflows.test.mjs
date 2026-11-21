import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

test('pages workflow exists and targets ./site with graceful summary fallback', () => {
  assert.ok(existsSync('.github/workflows/pages.yml'));
  const pages = readFileSync('.github/workflows/pages.yml', 'utf8');
  assert.match(pages, /actions\/upload-pages-artifact@v3/);
  assert.match(pages, /actions\/deploy-pages@v4/);
  assert.match(pages, /path:\s*'\.\/site'/);
  assert.match(pages, /workflow_dispatch/);
  assert.match(pages, /pages:\s*write/);
  assert.match(pages, /id-token:\s*write/);
  assert.match(pages, /GITHUB_STEP_SUMMARY/);

  const checkMatch = pages.match(/^  check:\n([\s\S]*?)^  deploy:\n/m);
  assert.ok(checkMatch, 'expected upstream check job before deploy job');
  const checkJob = checkMatch[1];
  assert.doesNotMatch(checkJob, /^\s*environment:/m, 'check job must not declare environment:');
  assert.match(checkJob, /^\s*outputs:\s*\n\s*enabled:\s*\$\{\{\s*steps\.check_pages\.outputs\.enabled\s*\}\}/m);
  assert.match(checkJob, /--max-time 15/);
  assert.match(checkJob, /build_type/);
  assert.match(checkJob, /workflow/);

  const deployMatch = pages.match(/^  deploy:\n([\s\S]*)$/m);
  assert.ok(deployMatch, 'expected deploy job');
  const deployJob = deployMatch[1];
  assert.match(deployJob, /^\s*needs:\s*check$/m);
  assert.match(deployJob, /^\s*if:\s*needs\.check\.outputs\.enabled == 'true'$/m);
  assert.match(deployJob, /^\s*environment:\s*\n\s*name:\s*github-pages/m);
});

test('ci workflow ignores site directory changes on both push and pull_request', () => {
  const ci = readFileSync('.github/workflows/ci.yml', 'utf8');
  const pushMatch = ci.match(/^  push:\n([\s\S]*?)^  pull_request:\n/m);
  assert.ok(pushMatch, 'expected push trigger block');
  assert.match(pushMatch[1], /paths-ignore:\s*\n\s*-\s*['"]site\/\*\*['"]\s*\n\s*-\s*['"]site-tests\/\*\*['"]/);

  const prMatch = ci.match(/^  pull_request:\n([\s\S]*?)^(?:  \w+:|\S)/m);
  assert.ok(prMatch, 'expected pull_request trigger block');
  assert.match(prMatch[1], /paths-ignore:\s*\n\s*-\s*['"]site\/\*\*['"]\s*\n\s*-\s*['"]site-tests\/\*\*['"]/);
});

test('README contains link to GitHub Pages website', () => {
  const readme = readFileSync('README.md', 'utf8');
  assert.match(readme, /\[Website\]\(https:\/\/413d\.github\.io\/henge\/\)/);
});
