import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const html = readFileSync('site/index.html', 'utf8');

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

function parseAttributes(rawAttrs) {
  const attrs = {};
  const attrRegex = /([a-zA-Z0-9:-]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g;
  for (const match of rawAttrs.matchAll(attrRegex)) {
    const name = match[1].toLowerCase();
    const value = match[2] ?? match[3] ?? match[4] ?? '';
    attrs[name] = value;
  }
  return attrs;
}

function getMetaContent(attrName, attrValue) {
  for (const match of html.matchAll(/<meta\b([^>]*)>/gi)) {
    const attrs = parseAttributes(match[1]);
    if (attrs[attrName] === attrValue) {
      return attrs.content ?? null;
    }
  }
  return null;
}

function getLinkHref(relValue) {
  for (const match of html.matchAll(/<link\b([^>]*)>/gi)) {
    const attrs = parseAttributes(match[1]);
    if (attrs.rel === relValue) {
      return attrs.href ?? null;
    }
  }
  return null;
}

test('Canonical URL, html lang, theme-color, and robots metadata are valid', () => {
  const htmlTagMatch = html.match(/<html\b([^>]*)>/i);
  assert.ok(htmlTagMatch, '<html> tag must exist');
  const htmlAttrs = parseAttributes(htmlTagMatch[1]);
  assert.match(htmlAttrs.lang || '', /^[a-z]{2}(?:-[A-Z]{2})?$/, '<html> must have a valid lang attribute');
  assert.equal(htmlAttrs.lang, 'en');

  assert.equal(
    getLinkHref('canonical'),
    'https://413d.github.io/henge/',
    'Canonical URL must point to https://413d.github.io/henge/'
  );

  assert.equal(
    getMetaContent('name', 'theme-color'),
    '#11121D',
    'theme-color must match canvas background #11121D'
  );

  const robots = getMetaContent('name', 'robots');
  if (robots !== null) {
    assert.doesNotMatch(robots, /\bnoindex\b/i, 'robots meta must not block indexing');
    assert.doesNotMatch(robots, /\bnofollow\b/i, 'robots meta must not set nofollow');
  }
});

test('Title and meta description length and quality are valid in EN HTML and EN/RU I18N', () => {
  const titleMatch = html.match(/<title>([\s\S]*?)<\/title>/i);
  assert.ok(titleMatch, '<title> tag must exist');
  const htmlTitle = titleMatch[1].trim();
  assert.ok(htmlTitle.length > 0 && htmlTitle.length <= 70, `HTML <title> must be <= 70 chars (got ${htmlTitle.length})`);

  const htmlDescription = getMetaContent('name', 'description');
  assert.ok(htmlDescription, '<meta name="description"> must exist');
  assert.ok(
    htmlDescription.length >= 50 && htmlDescription.length <= 160,
    `HTML meta description must be 50-160 chars (got ${htmlDescription.length})`
  );

  const I18N = loadI18N();
  for (const lang of ['en', 'ru']) {
    const dict = I18N[lang];
    assert.ok(dict, `Missing I18N dictionary for ${lang}`);

    const title = dict['meta.title'];
    assert.equal(typeof title, 'string');
    assert.ok(title.includes('Henge'), `${lang} meta.title must mention Henge`);
    assert.ok(title.length > 0 && title.length <= 70, `${lang} meta.title must be <= 70 chars (got ${title.length})`);

    const description = dict['meta.description'];
    assert.equal(typeof description, 'string');
    assert.ok(
      description.length >= 50 && description.length <= 160,
      `${lang} meta.description must be 50-160 chars (got ${description.length})`
    );
  }

  assert.equal(htmlTitle, I18N.en['meta.title']);
  assert.equal(htmlDescription, I18N.en['meta.description']);
});

test('OpenGraph and Twitter Card meta tags are complete and valid', () => {
  assert.equal(getMetaContent('property', 'og:type'), 'website');
  assert.equal(getMetaContent('property', 'og:site_name'), 'Henge');
  assert.equal(getMetaContent('property', 'og:url'), 'https://413d.github.io/henge/');
  assert.equal(getMetaContent('property', 'og:image'), 'https://413d.github.io/henge/assets/og-card.png');
  assert.equal(getMetaContent('property', 'og:image:width'), '1200');
  assert.equal(getMetaContent('property', 'og:image:height'), '630');

  const ogTitle = getMetaContent('property', 'og:title');
  assert.ok(ogTitle && ogTitle.includes('Henge') && ogTitle.length <= 70, 'og:title must be concise and mention Henge');

  const ogDescription = getMetaContent('property', 'og:description');
  assert.ok(
    ogDescription && ogDescription.length >= 50 && ogDescription.length <= 160,
    'og:description must be 50-160 chars'
  );

  assert.equal(getMetaContent('name', 'twitter:card'), 'summary_large_image');
  assert.equal(getMetaContent('name', 'twitter:image'), 'https://413d.github.io/henge/assets/og-card.png');

  const twitterTitle = getMetaContent('name', 'twitter:title');
  assert.ok(twitterTitle && twitterTitle.includes('Henge') && twitterTitle.length <= 70, 'twitter:title must be valid');

  const twitterDescription = getMetaContent('name', 'twitter:description');
  assert.ok(
    twitterDescription && twitterDescription.length >= 50 && twitterDescription.length <= 160,
    'twitter:description must be 50-160 chars'
  );

  assert.ok(existsSync('site/assets/og-card.png'), 'OG card image file must exist on disk');
});

test('Schema.org JSON-LD SoftwareApplication metadata parses and validates', () => {
  const ldMatch = html.match(/<script\s+type="application\/ld\+json">([\s\S]*?)<\/script>/i);
  assert.ok(ldMatch, 'JSON-LD script must exist');

  const jsonLd = JSON.parse(ldMatch[1]);
  assert.equal(jsonLd['@context'], 'https://schema.org');
  assert.equal(jsonLd['@type'], 'SoftwareApplication');
  assert.equal(jsonLd.name, 'Henge');
  assert.ok(typeof jsonLd.description === 'string' && jsonLd.description.length >= 50);
  assert.match(jsonLd.operatingSystem, /macOS/i);
  assert.equal(jsonLd.applicationCategory, 'UtilitiesApplication');
  assert.equal(jsonLd.offers?.['@type'], 'Offer');
  assert.equal(jsonLd.offers?.price, '0');
  assert.equal(jsonLd.offers?.priceCurrency, 'USD');

  for (const field of ['url', 'downloadUrl', 'license', 'image', 'softwareHelp']) {
    assert.equal(typeof jsonLd[field], 'string', `JSON-LD ${field} must be a string`);
    const parsed = new URL(jsonLd[field]);
    assert.equal(parsed.protocol, 'https:', `JSON-LD ${field} must use HTTPS`);
  }
});

test('Heading hierarchy has single <h1>, non-empty <h2> sections, and no skipped levels', () => {
  const headings = [];
  for (const match of html.matchAll(/<(h[1-6])\b[^>]*>([\s\S]*?)<\/\1>/gi)) {
    const level = Number(match[1].slice(1));
    const text = match[2].replace(/<[^>]+>/g, '').trim();
    headings.push({ level, text });
  }

  const h1s = headings.filter((h) => h.level === 1);
  assert.equal(h1s.length, 1, 'Page must contain exactly one <h1>');
  assert.ok(h1s[0].text.length > 0, '<h1> must have non-empty text');

  const h2s = headings.filter((h) => h.level === 2);
  assert.ok(h2s.length >= 3, 'Page must contain section <h2> headings');
  for (const h2 of h2s) {
    assert.ok(h2.text.length > 0, 'Every <h2> must have non-empty text');
  }

  assert.equal(headings[0].level, 1, 'First heading in document must be <h1>');
  for (let i = 1; i < headings.length; i += 1) {
    const prev = headings[i - 1];
    const curr = headings[i];
    assert.ok(
      curr.level <= prev.level + 1,
      `Skipped heading level from <h${prev.level}> ("${prev.text}") to <h${curr.level}> ("${curr.text}")`
    );
  }
});

test('All images have accessible alt attributes and point to existing local ./assets/ files', () => {
  const imgs = [...html.matchAll(/<img\b([^>]*)>/gi)];
  assert.ok(imgs.length > 0, 'Expected at least one <img> in site/index.html');

  for (const match of imgs) {
    const attrs = parseAttributes(match[1]);
    assert.ok('alt' in attrs, `<img> missing alt attribute: ${match[0]}`);

    const isDecorative = attrs['aria-hidden'] === 'true';
    if (!isDecorative) {
      assert.ok(attrs.alt.trim().length > 0, `Non-decorative <img> must have non-empty alt text: ${match[0]}`);
    }

    assert.ok(typeof attrs.src === 'string' && attrs.src.startsWith('./assets/'), `<img> src must be relative ./assets/: ${attrs.src}`);
    const resolved = path.join('site', attrs.src);
    assert.ok(existsSync(resolved), `Referenced image does not exist on disk: ${resolved}`);
  }

  for (const rel of ['icon', 'apple-touch-icon', 'stylesheet']) {
    const href = getLinkHref(rel);
    assert.ok(href && href.startsWith('./'), `<link rel="${rel}"> must use relative ./ path (got ${href})`);
    assert.ok(existsSync(path.join('site', href)), `Referenced link asset missing: site/${href}`);
  }
});

test('Zero external runtime dependencies, CDNs, remote fonts, or trackers', () => {
  for (const match of html.matchAll(/<script\b([^>]*)>/gi)) {
    const attrs = parseAttributes(match[1]);
    if (attrs.src) {
      assert.doesNotMatch(attrs.src, /^(?:https?:)?\/\//i, `External script disallowed: ${attrs.src}`);
      assert.ok(attrs.src.startsWith('./'), `Local script must use relative path: ${attrs.src}`);
      assert.ok(existsSync(path.join('site', attrs.src)), `Local script missing on disk: ${attrs.src}`);
    }
  }

  for (const match of html.matchAll(/<link\b([^>]*)>/gi)) {
    const attrs = parseAttributes(match[1]);
    if (attrs.rel === 'stylesheet' && attrs.href) {
      assert.doesNotMatch(attrs.href, /^(?:https?:)?\/\//i, `External stylesheet disallowed: ${attrs.href}`);
    }
  }

  const forbiddenPatterns = [
    /fonts\.googleapis\.com/i,
    /fonts\.gstatic\.com/i,
    /cdn\.jsdelivr\.net/i,
    /unpkg\.com/i,
    /cdnjs\.cloudflare\.com/i,
    /googletagmanager\.com/i,
    /google-analytics\.com/i,
    /\bgtag\s*\(/i,
    /plausible\.io/i,
    /umami/i
  ];
  for (const pattern of forbiddenPatterns) {
    assert.doesNotMatch(html, pattern, `Forbidden external dependency/tracker pattern matched: ${pattern}`);
  }
});

test('All internal anchor links (#id) resolve to existing element IDs', () => {
  const ids = new Set();
  for (const match of html.matchAll(/\sid="([^"]+)"/g)) {
    ids.add(match[1]);
  }

  const anchorLinks = [...html.matchAll(/href="#([^"]+)"/g)];
  assert.ok(anchorLinks.length > 0, 'Expected internal anchor links in site/index.html');

  for (const match of anchorLinks) {
    const targetId = match[1];
    assert.ok(ids.has(targetId), `Internal anchor href="#${targetId}" has no matching element id`);
  }
});
