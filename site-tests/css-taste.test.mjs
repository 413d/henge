import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const css = readFileSync('site/styles.css', 'utf8');

test('CSS adheres to anti-slop rules: single gray family, locked accent, shape lock', () => {
  // Accent color locked to narutomaki coral #F08C70
  assert.match(css, /--accent:\s*#F08C70/i);
  assert.match(css, /--bg-canvas:\s*#141722/i);
  assert.match(css, /--bg-surface:\s*#1B1F2E/i);
  assert.match(css, /--bg-elevated:\s*#23283B/i);

  // Shape lock: 999px (pills), 16px (cards/containers), 8px (controls)
  assert.match(css, /--radius-full:\s*999px/);
  assert.match(css, /--radius-card:\s*16px/);
  assert.match(css, /--radius-control:\s*8px/);

  // No AI-default gradient buttons or purple/indigo/cyan glows
  assert.doesNotMatch(css, /linear-gradient\(.*#8A2BE2/i);
  assert.doesNotMatch(css, /linear-gradient\(.*#6366F1/i);
  assert.doesNotMatch(css, /#8A2BE2/i);
  assert.doesNotMatch(css, /#6366F1/i);

  // Reduced motion media query present
  assert.match(css, /@media\s*\(prefers-reduced-motion:\s*reduce\)/);
});

test('CSS styles interactive state classes, focus-visible, and semantic status token', () => {
  assert.match(css, /:focus-visible\b/);
  assert.match(css, /\.is-active\b/);
  assert.match(css, /\.is-pressed\b/);
  assert.match(css, /\.is-converted\b/);
  assert.match(css, /\.is-copied\b/);
  assert.match(css, /\.is-success\b/);
  assert.match(css, /\.is-muted\b/);
  assert.match(css, /--status-green:\s*#32D74B/i);
});

test('CSS includes responsive breakpoints and avoids unintended i18n pending opacity override', () => {
  assert.match(css, /@media\s*\(max-width:\s*920px\)|@media\s*\(max-width:\s*900px\)|@media\s*\(max-width:\s*860px\)/);
  assert.match(css, /@media\s*\(max-width:\s*540px\)/);
  assert.doesNotMatch(css, /html\.is-i18n-pending\s+body\s*\{[^}]*opacity:\s*1/i);
});
