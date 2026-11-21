import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

test('pages workflow exists, splits build and deploy jobs, and targets ./site with graceful summary fallback', () => {
  assert.ok(existsSync('.github/workflows/pages.yml'));
  const pages = readFileSync('.github/workflows/pages.yml', 'utf8');
  assert.match(pages, /actions\/configure-pages@v6/);
  assert.match(pages, /actions\/upload-pages-artifact@v5/);
  assert.match(pages, /actions\/deploy-pages@v5/);
  assert.match(pages, /path:\s*'\.\/site'/);
  assert.match(pages, /include-hidden-files:\s*'true'/);
  assert.match(pages, /workflow_dispatch/);
  assert.match(pages, /pages:\s*write/);
  assert.match(pages, /id-token:\s*write/);
  assert.match(pages, /GITHUB_STEP_SUMMARY/);

  const checkMatch = pages.match(/^  check:\n([\s\S]*?)^  build:\n/m);
  assert.ok(checkMatch, 'expected upstream check job before build job');
  const checkJob = checkMatch[1];
  assert.doesNotMatch(checkJob, /^\s*environment:/m, 'check job must not declare environment:');
  assert.match(checkJob, /^\s*outputs:\s*\n\s*enabled:\s*\$\{\{\s*steps\.check_pages\.outputs\.enabled\s*\}\}/m);
  assert.match(checkJob, /--max-time 15/);
  assert.match(checkJob, /build_type/);
  assert.match(checkJob, /workflow/);

  const buildMatch = pages.match(/^  build:\n([\s\S]*?)^  deploy:\n/m);
  assert.ok(buildMatch, 'expected dedicated build job between check and deploy');
  const buildJob = buildMatch[1];
  assert.doesNotMatch(buildJob, /^\s*environment:/m, 'build job must not declare environment:');
  assert.match(buildJob, /^\s*needs:\s*check$/m);
  assert.match(buildJob, /^\s*if:\s*needs\.check\.outputs\.enabled == 'true'$/m);
  assert.match(buildJob, /node --test[\s\S]*site-tests\/html-structure\.test\.mjs/);
  assert.match(buildJob, /actions\/upload-pages-artifact@v5/);
  assert.doesNotMatch(buildJob, /actions\/deploy-pages/);

  const deployMatch = pages.match(/^  deploy:\n([\s\S]*)$/m);
  assert.ok(deployMatch, 'expected dedicated deploy job');
  const deployJob = deployMatch[1];
  assert.match(deployJob, /^\s*needs:\s*\[check,\s*build\]$/m);
  assert.match(deployJob, /^\s*if:\s*needs\.check\.outputs\.enabled == 'true'$/m);
  assert.match(deployJob, /^\s*environment:\s*\n\s*name:\s*github-pages/m);
  assert.doesNotMatch(deployJob, /actions\/upload-pages-artifact/, 'deploy job must not upload artifacts in the same job');
  assert.match(deployJob, /actions\/deploy-pages@v5/);
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

test('release workflow uploads INSTALL.txt and documents Homebrew, curl installer, official Apple Open Anyway flow, and xattr', () => {
  const release = readFileSync('.github/workflows/release.yml', 'utf8');
  assert.match(release, /dist\/INSTALL\.txt/);
  assert.match(release, /brew tap 413d\/henge https:\/\/github\.com\/413d\/henge/);
  assert.match(release, /brew install --cask 413d\/henge\/henge/);
  assert.match(release, /raw\.githubusercontent\.com\/413d\/henge\/main\/scripts\/install\.sh/);
  assert.match(release, /Open Anyway/);
  assert.match(release, /System Settings\s*→\s*Privacy & Security/);
  assert.match(release, /xattr -dr com\.apple\.quarantine/);
});
