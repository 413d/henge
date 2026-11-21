import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

test('required static assets exist with valid dimensions', () => {
  assert.ok(fs.existsSync('site/.nojekyll'), '.nojekyll must exist');
  const files = [
    { path: 'site/assets/icon-256.png', w: 256, h: 256 },
    { path: 'site/assets/icon-128.png', w: 128, h: 128 },
    { path: 'site/assets/favicon-32.png', w: 32, h: 32 },
    { path: 'site/assets/apple-touch-icon.png', w: 180, h: 180 },
    { path: 'site/assets/menubar-icon.png', w: 44, h: 44 },
    { path: 'site/assets/og-card.png', w: 1200, h: 630 }
  ];
  for (const f of files) {
    assert.ok(fs.existsSync(f.path), `Missing ${f.path}`);
    const stat = fs.statSync(f.path);
    assert.ok(stat.size > 100, `${f.path} is too small (${stat.size} bytes)`);
    const output = execFileSync('/usr/bin/sips', ['-g', 'pixelWidth', '-g', 'pixelHeight', f.path], { encoding: 'utf8' });
    assert.match(output, new RegExp(`pixelWidth: ${f.w}`));
    assert.match(output, new RegExp(`pixelHeight: ${f.h}`));
  }
});
