import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
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
      querySelectorAll: () => [],
    },
    navigator: { languages: ['en-US'], language: 'en-US' },
    localStorage: { getItem: () => null, setItem: () => {} },
    location: { search: '' },
    setTimeout,
    clearTimeout,
  };
  vm.runInNewContext(code, sandbox);
  return sandbox.window.HengeCore.I18N;
}

const I18N = loadI18N();

const html = readFileSync('site/index.html', 'utf8');
const robots = readFileSync('site/robots.txt', 'utf8');
const sitemap = readFileSync('site/sitemap.xml', 'utf8');
const llmsTxt = readFileSync('site/llms.txt', 'utf8');
const llmsFull = readFileSync('site/llms-full.txt', 'utf8');

test('robots.txt allows standard and AI search crawlers and declares sitemap', () => {
  assert.ok(existsSync('site/robots.txt'));
  assert.doesNotMatch(robots, /^Disallow:\s*\/\s*$/m, 'robots.txt must not block site root');

  for (const agent of [
    '*',
    'OAI-SearchBot',
    'ChatGPT-User',
    'GPTBot',
    'PerplexityBot',
    'ClaudeBot',
    'anthropic-ai',
    'Google-Extended',
    'Applebot-Extended',
  ]) {
    assert.ok(
      robots.includes(`User-agent: ${agent}`),
      `robots.txt should explicitly welcome ${agent}`
    );
  }

  assert.match(
    robots,
    /^Sitemap:\s*https:\/\/413d\.github\.io\/henge\/sitemap\.xml\s*$/m,
    'robots.txt must declare canonical sitemap URL'
  );
});

test('sitemap.xml declares canonical landing page and llms.txt endpoints', () => {
  assert.ok(existsSync('site/sitemap.xml'));
  assert.match(sitemap, /<\?xml\s+version="1\.0"\s+encoding="UTF-8"\?>/);
  assert.match(sitemap, /<urlset\s+xmlns="http:\/\/www\.sitemaps\.org\/schemas\/sitemap\/0\.9">/);

  for (const loc of [
    'https://413d.github.io/henge/',
    'https://413d.github.io/henge/llms.txt',
    'https://413d.github.io/henge/llms-full.txt',
  ]) {
    assert.ok(sitemap.includes(`<loc>${loc}</loc>`), `sitemap.xml missing <loc>${loc}</loc>`);
  }
});

test('llms.txt and llms-full.txt follow llmstxt structure with bilingual accurate facts', () => {
  assert.match(llmsTxt, /^# Henge\b/m);
  assert.match(llmsTxt, /^> .+macOS 13\+.+⌥X/m);
  assert.ok(llmsTxt.includes('https://413d.github.io/henge/llms-full.txt'));
  assert.ok(llmsTxt.includes('https://github.com/413d/henge/releases'));
  assert.ok(llmsTxt.includes('AXSecureTextField'));
  assert.ok(llmsTxt.includes('xattr -dr com.apple.quarantine'));
  assert.ok(llmsTxt.includes('Open Anyway'), 'llms.txt must mention Apple official Open Anyway flow');
  assert.ok(llmsTxt.includes('brew tap 413d/henge'), 'llms.txt must mention Homebrew tap install');
  assert.ok(
    llmsTxt.includes('https://raw.githubusercontent.com/413d/henge/main/scripts/install.sh'),
    'llms.txt must mention curl install script'
  );

  assert.match(llmsFull, /^# Henge\b/m);
  assert.ok(llmsFull.includes('Punto Switcher'), 'llms-full.txt should address automatic-switcher comparisons');
  assert.ok(llmsFull.includes('ghbdtn') && llmsFull.includes('привет'));
  assert.ok(llmsFull.includes('руддщ') && llmsFull.includes('hello'));
  assert.ok(llmsFull.includes('Частые вопросы'), 'llms-full.txt must include Russian Q&A for Cyrillic prompts');
  assert.ok(llmsFull.includes('Frequently Asked Questions'), 'llms-full.txt must include English Q&A');
  assert.ok(llmsFull.includes('Open Anyway') && llmsFull.includes('Всё равно открыть'));
  assert.ok(llmsFull.includes('brew tap 413d/henge'));
  assert.ok(llmsFull.includes('https://raw.githubusercontent.com/413d/henge/main/scripts/install.sh'));
});

test('HTML exposes llms discovery links, SoftwareApplication features, and FAQPage JSON-LD', () => {
  assert.match(html, /<link\s+rel="alternate"\s+type="text\/markdown"[^>]+href="\.\/llms\.txt"/i);
  assert.match(html, /<link\s+rel="alternate"\s+type="text\/markdown"[^>]+href="\.\/llms-full\.txt"/i);
  assert.match(html, /<a\s+href="\.\/llms\.txt">llms\.txt<\/a>/i);

  const ldBlocks = [...html.matchAll(/<script\s+type="application\/ld\+json">([\s\S]*?)<\/script>/gi)];
  assert.equal(ldBlocks.length, 2, 'Expected SoftwareApplication and FAQPage JSON-LD scripts');

  const appLd = JSON.parse(ldBlocks[0][1]);
  assert.equal(appLd['@type'], 'SoftwareApplication');
  assert.equal(appLd.isAccessibleForFree, true);
  assert.ok(Array.isArray(appLd.featureList) && appLd.featureList.length >= 4);
  assert.ok(typeof appLd.keywords === 'string' && appLd.keywords.includes('Punto Switcher'));

  const faqLd = JSON.parse(ldBlocks[1][1]);
  assert.equal(faqLd['@context'], 'https://schema.org');
  assert.equal(faqLd['@type'], 'FAQPage');
  assert.ok(Array.isArray(faqLd.mainEntity) && faqLd.mainEntity.length === 5);

  for (let i = 0; i < faqLd.mainEntity.length; i += 1) {
    const item = faqLd.mainEntity[i];
    assert.equal(item['@type'], 'Question');
    assert.ok(typeof item.name === 'string' && item.name.endsWith('?'));
    assert.equal(item.acceptedAnswer?.['@type'], 'Answer');
    assert.ok(typeof item.acceptedAnswer?.text === 'string' && item.acceptedAnswer.text.length >= 40);

    const idx = i + 1;
    assert.ok(html.includes(`data-i18n="faq.q${idx}"`), `HTML missing faq.q${idx}`);
    assert.ok(html.includes(`data-i18n="faq.a${idx}"`), `HTML missing faq.a${idx}`);
    assert.ok(typeof I18N.en[`faq.q${idx}`] === 'string' && typeof I18N.ru[`faq.q${idx}`] === 'string');
    assert.ok(typeof I18N.en[`faq.a${idx}`] === 'string' && typeof I18N.ru[`faq.a${idx}`] === 'string');
  }

  assert.match(faqLd.mainEntity[3].acceptedAnswer.text, /Open Anyway/);
  assert.match(faqLd.mainEntity[3].acceptedAnswer.text, /xattr -dr com\.apple\.quarantine/);
  assert.match(I18N.en['faq.a4'], /Open Anyway/);
  assert.match(I18N.en['faq.a4'], /xattr -dr com\.apple\.quarantine/);
  assert.match(I18N.ru['faq.a4'], /Всё равно открыть/);
  assert.match(I18N.ru['faq.a4'], /xattr -dr com\.apple\.quarantine/);
});

test('README.md and SECURITY.md document Homebrew, curl installer, Apple Open Anyway, and xattr', () => {
  const readme = readFileSync('README.md', 'utf8');
  const security = readFileSync('SECURITY.md', 'utf8');

  assert.match(readme, /brew tap 413d\/henge https:\/\/github\.com\/413d\/henge/);
  assert.match(readme, /brew install --cask 413d\/henge\/henge/);
  assert.match(readme, /curl -fsSL https:\/\/raw\.githubusercontent\.com\/413d\/henge\/main\/scripts\/install\.sh \| bash/);
  assert.match(readme, /Privacy & Security → Open Anyway|Privacy &amp; Security → Open Anyway/);
  assert.match(readme, /official|Apple/i);
  assert.match(readme, /xattr -dr com\.apple\.quarantine/);

  assert.match(security, /Open Anyway/);
  assert.match(security, /xattr -dr com\.apple\.quarantine/);
  assert.match(security, /brew install --cask 413d\/henge\/henge/);
});
