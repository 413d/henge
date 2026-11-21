import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

function loadI18N() {
  const code = readFileSync('site/app.js', 'utf8');
  const sandbox = {
    window: {},
    document: {
      documentElement: { lang: 'en' },
      title: '',
      addEventListener: () => {},
      querySelector: () => null,
      querySelectorAll: () => []
    },
    navigator: { languages: ['en-US'], language: 'en-US' },
    localStorage: { getItem: () => null, setItem: () => {} },
    location: { search: '' },
    setTimeout,
    clearTimeout
  };
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox);
  return sandbox.window.HengeCore.I18N;
}

const html = readFileSync('site/index.html', 'utf8');

test('HTML contains valid head metadata and relative asset paths', () => {
  assert.match(html, /<!DOCTYPE html>/i);
  assert.match(html, /<meta name="viewport" content="width=device-width, initial-scale=1/);
  assert.match(html, /<link rel="canonical" href="https:\/\/413d\.github\.io\/henge\/"/);
  assert.match(html, /<meta property="og:url" content="https:\/\/413d\.github\.io\/henge\/"/);
  assert.match(html, /<meta property="og:type" content="website"/);
  assert.match(html, /<meta property="og:image" content="https:\/\/413d\.github\.io\/henge\/assets\/og-card\.png"/);
  assert.match(html, /<meta property="og:image:width" content="1200"/);
  assert.match(html, /<meta property="og:image:height" content="630"/);
  assert.match(html, /<meta name="twitter:card" content="summary_large_image"/);
  assert.match(html, /<meta name="theme-color" content="#141722"/);
  assert.match(html, /href="\.\/styles\.css"/, 'CSS path must be relative');
  assert.match(html, /src="\.\/app\.js"/, 'JS path must be relative');
  assert.match(html, /href="\.\/assets\/favicon-32\.png"/);
  assert.match(html, /href="\.\/assets\/apple-touch-icon\.png"/);
  assert.match(html, /src="\.\/assets\/icon-128\.png"/);
  assert.match(html, /src="\.\/assets\/menubar-icon\.png"/);
  assert.doesNotMatch(html, /(?:href|src)="\/(?:styles\.css|app\.js|assets\/)/, 'Asset paths must not be root-relative');
  assert.match(html, /application\/ld\+json/);

  const ldMatch = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/);
  assert.ok(ldMatch, 'JSON-LD script must exist');
  const jsonLd = JSON.parse(ldMatch[1]);
  assert.equal(jsonLd['@type'], 'SoftwareApplication');
  assert.equal(jsonLd.operatingSystem, 'macOS 13+');
  assert.equal(jsonLd.downloadUrl, 'https://github.com/413d/henge/releases/latest');
  assert.equal(jsonLd.offers?.price, '0');
});

test('HTML includes early language bootstrap preventing EN-to-RU flash', () => {
  const headMatch = html.match(/<head>([\s\S]*?)<\/head>/i);
  assert.ok(headMatch, '<head> must exist');
  const head = headMatch[1];
  assert.match(head, /is-i18n-pending/);
  assert.match(head, /localStorage\.getItem\(['"]henge_lang['"]\)/);
  assert.match(head, /navigator\.languages/);
  assert.match(head, /document\.documentElement\.lang/);
});

test('HTML contains all required sections, semantics, and interactive elements', () => {
  assert.match(html, /<header/);
  assert.match(html, /<main/);
  assert.match(html, /id="hero"/);
  assert.match(html, /id="demo"/);
  assert.match(html, /id="features"/);
  assert.match(html, /id="privacy"/);
  assert.match(html, /id="install"/);
  assert.match(html, /<footer/);

  // Single h1 inside hero
  const h1Matches = html.match(/<h1\b/g) || [];
  assert.equal(h1Matches.length, 1, 'Page must have exactly one <h1>');

  // Demo elements and accessible label
  assert.match(html, /<label\b[^>]*for="demo-input"/);
  assert.match(html, /id="demo-input"/);
  assert.match(html, />Ghbdtn, vbh!<\/textarea>/);
  assert.match(html, /id="demo-fix-btn"/);
  assert.match(html, /id="demo-status"/);
  assert.match(html, /data-chip=/);

  // Install command copy button and target
  assert.match(html, /id="copy-xattr-btn"/);
  assert.match(html, /id="xattr-cmd"/);
  assert.match(html, /xattr -dr com\.apple\.quarantine/);

  // Language switch
  assert.match(html, /data-lang-btn="ru"/);
  assert.match(html, /data-lang-btn="en"/);

  // Zero emojis in UI chrome
  assert.doesNotMatch(html, /(?:\p{Emoji_Presentation}|[\u{1F300}-\u{1FAFF}])/u, 'UI chrome must not contain emojis');
});

test('Every data-i18n* key in site/index.html exists in site/app.js I18N.en and I18N.ru', () => {
  const I18N = loadI18N();
  const attrRegex = /data-i18n(?:-(?:placeholder|aria))?="([^"]+)"/g;
  const foundKeys = new Set();
  for (const match of html.matchAll(attrRegex)) {
    foundKeys.add(match[1]);
  }
  assert.ok(foundKeys.size > 0, 'Expected data-i18n* attributes in site/index.html');

  for (const key of foundKeys) {
    assert.ok(key in I18N.en, `data-i18n key "${key}" missing in I18N.en`);
    assert.ok(key in I18N.ru, `data-i18n key "${key}" missing in I18N.ru`);
  }
});
