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
});

test('ci workflow ignores site directory changes to prevent slow unnecessary runs', () => {
  const ci = readFileSync('.github/workflows/ci.yml', 'utf8');
  assert.match(ci, /paths-ignore:\s*\n\s*-\s*['"]site\/\*\*['"]/);
  assert.match(ci, /-\s*['"]site-tests\/\*\*['"]/);
});

test('README contains link to GitHub Pages website', () => {
  const readme = readFileSync('README.md', 'utf8');
  assert.match(readme, /\[Website\]\(https:\/\/413d\.github\.io\/henge\/\)/);
});
