import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

function loadHengeCore(overrides = {}) {
  const code = readFileSync('site/app.js', 'utf8');
  const storage = new Map(Object.entries(overrides.storage || {}));
  const sandbox = {
    window: {},
    document: overrides.document || {
      documentElement: { lang: 'en' },
      title: '',
      addEventListener: () => {},
      querySelector: () => null,
      querySelectorAll: () => []
    },
    navigator: overrides.navigator || {
      languages: ['en-US'],
      language: 'en-US',
      clipboard: { writeText: async () => {} }
    },
    localStorage: overrides.localStorage || {
      getItem: (k) => (storage.has(k) ? storage.get(k) : null),
      setItem: (k, v) => {
        storage.set(k, String(v));
      }
    },
    location: overrides.location || { search: '' },
    setTimeout,
    clearTimeout
  };
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox);
  return { HengeCore: sandbox.window.HengeCore, HengeDemo: sandbox.window.HengeDemo, sandbox, storage };
}

function plain(obj) {
  return { ...obj };
}

test('HengeCore layout detection matches Swift MajorityLayoutDetector', () => {
  const { HengeCore, HengeDemo } = loadHengeCore();
  assert.equal(HengeCore, HengeDemo);

  assert.deepEqual(plain(HengeCore.detectLayout('ghbdtn')), { layout: 'en', confidence: 'clear' });
  assert.deepEqual(plain(HengeCore.detectLayout('привет')), { layout: 'ru', confidence: 'clear' });
  assert.deepEqual(plain(HengeCore.detectLayout('ёлка')), { layout: 'ru', confidence: 'clear' });
  assert.deepEqual(plain(HengeCore.detectLayout('12345')), { layout: null, confidence: 'neutral' });
  assert.deepEqual(plain(HengeCore.detectLayout('!!!')), { layout: null, confidence: 'neutral' });
  assert.deepEqual(plain(HengeCore.detectLayout('')), { layout: null, confidence: 'neutral' });
  assert.deepEqual(plain(HengeCore.detectLayout('ghbdtn привет')), { layout: null, confidence: 'ambiguous' });
  assert.deepEqual(plain(HengeCore.detectLayout('abвг')), { layout: null, confidence: 'ambiguous' });
  assert.deepEqual(plain(HengeCore.detectLayout('ghbdtn я')), { layout: 'en', confidence: 'clear' });
  assert.deepEqual(plain(HengeCore.detectLayout('привет a')), { layout: 'ru', confidence: 'clear' });
});

test('HengeCore transformation preserves case, digits, _, and delimited punctuation', () => {
  const { HengeCore } = loadHengeCore();

  assert.deepEqual(plain(HengeCore.transformText('ghbdtn')), { status: 'transformed', text: 'привет' });
  assert.deepEqual(plain(HengeCore.transformText('Ghbdtn, vbh!')), { status: 'transformed', text: 'Привет, мир!' });
  assert.deepEqual(plain(HengeCore.transformText('GhBdTn')), { status: 'transformed', text: 'ПрИвЕт' });
  assert.deepEqual(plain(HengeCore.transformText('руддщ цщкдв')), { status: 'transformed', text: 'hello world' });
  assert.deepEqual(plain(HengeCore.transformText('привет')), { status: 'transformed', text: 'ghbdtn' });
  assert.deepEqual(plain(HengeCore.transformText('ghbdtn_2026')), { status: 'transformed', text: 'привет_2026' });
  assert.deepEqual(plain(HengeCore.transformText(',kby — c.lf!')), { status: 'transformed', text: 'блин — сюда!' });
  assert.deepEqual(plain(HengeCore.transformText(';bpym')), { status: 'transformed', text: 'жизнь' });
  assert.deepEqual(plain(HengeCore.transformText('`kby')), { status: 'transformed', text: 'ёлин' });
  assert.deepEqual(plain(HengeCore.transformText('~')), { status: 'noOp', text: '~', reason: 'neutralText' });

  // No-op reasons match SimpleTextTransformer
  assert.deepEqual(plain(HengeCore.transformText('')), { status: 'noOp', text: '', reason: 'emptyText' });
  assert.deepEqual(plain(HengeCore.transformText('12345')), { status: 'noOp', text: '12345', reason: 'neutralText' });
  assert.deepEqual(plain(HengeCore.transformText('abвг')), { status: 'noOp', text: 'abвг', reason: 'ambiguousDirection' });
});

test('HengeCore selection vs caret word boundary logic matches DefaultWordBoundaryDetector', () => {
  const { HengeCore } = loadHengeCore();

  // Selection present
  const full = 'start ghbdtn end';
  const selRes = HengeCore.fixTextAtSelection(full, 6, 12);
  assert.equal(selRes.newValue, 'start привет end');
  assert.equal(selRes.newStart, 6);
  assert.equal(selRes.newEnd, 12);
  assert.equal(selRes.changed, true);

  // Caret inside word
  const caretInside = HengeCore.fixTextAtSelection(full, 9, 9);
  assert.equal(caretInside.newValue, 'start привет end');
  assert.equal(caretInside.changed, true);

  // Caret at start and end of standalone word
  assert.equal(HengeCore.fixTextAtSelection('ghbdtn', 0, 0).newValue, 'привет');
  assert.equal(HengeCore.fixTextAtSelection('ghbdtn', 6, 6).newValue, 'привет');

  // Caret following delimited punctuation
  const afterPunct = HengeCore.fixTextAtSelection('ghbdtn, ', 8, 8);
  assert.equal(afterPunct.newValue, 'привет, ');
  assert.equal(afterPunct.changed, true);

  // Word wrapped in punctuation
  const wrapped = HengeCore.fixTextAtSelection('(ghbdtn)!', 9, 9);
  assert.equal(wrapped.newValue, '(привет)!');
  assert.equal(wrapped.changed, true);

  // Digits and underscore preserved as part of token
  const withDigits = HengeCore.fixTextAtSelection('ghbdtn_123', 10, 10);
  assert.equal(withDigits.newValue, 'привет_123');
  assert.equal(withDigits.changed, true);

  // Neutral / empty no-ops
  assert.equal(HengeCore.fixTextAtSelection('!!!', 1, 1).changed, false);
  assert.equal(HengeCore.fixTextAtSelection(' ', 1, 1).changed, false);
  assert.equal(HengeCore.fixTextAtSelection('', 0, 0).changed, false);
});

test('HengeCore i18n dictionary covers all required keys in RU and EN symmetrically', () => {
  const { HengeCore } = loadHengeCore();
  const { I18N } = HengeCore;
  assert.ok(I18N.en && I18N.ru);

  const requiredKeys = [
    'meta.title', 'meta.description',
    'nav.features', 'nav.privacy', 'nav.install', 'nav.github', 'nav.langLabel',
    'hero.eyebrow', 'hero.title', 'hero.subtitle', 'hero.ctaDownload', 'hero.ctaGithub', 'hero.meta',
    'demo.windowTitle', 'demo.menubarEnabled', 'demo.menubarShortcut', 'demo.menubarAccessibility',
    'demo.label', 'demo.placeholder', 'demo.fixBtn', 'demo.hint',
    'demo.statusReady', 'demo.statusConverted', 'demo.statusAmbiguous', 'demo.statusNoOp', 'demo.chipLabel',
    'features.eyebrow', 'features.title', 'features.subtitle',
    'features.c1Title', 'features.c1Desc', 'features.c2Title', 'features.c2Desc',
    'features.c3Title', 'features.c3Desc', 'features.c4Title', 'features.c4Desc',
    'privacy.eyebrow', 'privacy.title', 'privacy.subtitle',
    'privacy.c1Title', 'privacy.c1Desc', 'privacy.c2Title', 'privacy.c2Desc', 'privacy.c3Title', 'privacy.c3Desc',
    'privacy.limitsTitle', 'privacy.limitsItem1', 'privacy.limitsItem2', 'privacy.limitsItem3',
    'install.eyebrow', 'install.title', 'install.subtitle',
    'install.brewBadge', 'install.brewTitle', 'install.brewDesc',
    'install.curlBadge', 'install.curlTitle', 'install.curlDesc',
    'install.manualTitle',
    'install.s1Title', 'install.s1Desc', 'install.s2Title', 'install.s2Desc',
    'install.s2GuiLabel', 'install.s2GuiDesc', 'install.s2CliLabel',
    'install.s2Explain', 'install.s2Verify', 'install.s3Title', 'install.s3Desc',
    'install.copyBtn', 'install.copiedBtn',
    'footer.license', 'footer.releases', 'footer.issues', 'footer.architecture',
    'footer.buildFromSource', 'footer.buildHint'
  ];

  for (const key of requiredKeys) {
    assert.ok(typeof I18N.en[key] === 'string' && I18N.en[key].length > 0, `Missing EN translation for ${key}`);
    assert.ok(typeof I18N.ru[key] === 'string' && I18N.ru[key].length > 0, `Missing RU translation for ${key}`);
  }

  for (const key of Object.keys(I18N.en)) {
    assert.ok(typeof I18N.ru[key] === 'string' && I18N.ru[key].length > 0, `Missing RU translation for ${key}`);
  }
  for (const key of Object.keys(I18N.ru)) {
    assert.ok(typeof I18N.en[key] === 'string' && I18N.en[key].length > 0, `Extra RU translation key not in EN: ${key}`);
  }
});

test('HengeCore resolves initial language by URL param > localStorage > navigator', () => {
  assert.equal(
    loadHengeCore({ location: { search: '?lang=ru' }, storage: { henge_lang: 'en' }, navigator: { languages: ['en-US'] } })
      .HengeCore.resolveInitialLanguage(),
    'ru'
  );
  assert.equal(
    loadHengeCore({ location: { search: '?lang=en' }, storage: { henge_lang: 'ru' }, navigator: { languages: ['ru-RU'] } })
      .HengeCore.resolveInitialLanguage(),
    'en'
  );
  assert.equal(
    loadHengeCore({ location: { search: '' }, storage: { henge_lang: 'ru' }, navigator: { languages: ['en-US'] } })
      .HengeCore.resolveInitialLanguage(),
    'ru'
  );
  assert.equal(
    loadHengeCore({ location: { search: '' }, storage: {}, navigator: { languages: ['ru-RU', 'en-US'] } })
      .HengeCore.resolveInitialLanguage(),
    'ru'
  );
  assert.equal(
    loadHengeCore({ location: { search: '' }, storage: {}, navigator: { languages: ['fr-FR'], language: 'fr-FR' } })
      .HengeCore.resolveInitialLanguage(),
    'en'
  );
});

test('HengeCore setLanguage updates DOM bindings and localStorage and copyToClipboard reports status', async () => {
  const metaDesc = { attrs: {}, setAttribute(k, v) { this.attrs[k] = v; } };
  const textNode = {
    textContent: '',
    getAttribute(k) {
      return k === 'data-i18n' ? 'hero.title' : null;
    }
  };
  const placeholderNode = {
    attrs: {},
    getAttribute(k) {
      return k === 'data-i18n-placeholder' ? 'demo.placeholder' : null;
    },
    setAttribute(k, v) {
      this.attrs[k] = v;
    }
  };
  const ariaNode = {
    attrs: {},
    getAttribute(k) {
      return k === 'data-i18n-aria' ? 'nav.langLabel' : null;
    },
    setAttribute(k, v) {
      this.attrs[k] = v;
    }
  };
  const makeLangBtn = (lang) => ({
    attrs: {},
    classes: new Set(),
    classList: {
      toggle(cls, force) {
        if (force) this._owner.classes.add(cls);
        else this._owner.classes.delete(cls);
      }
    },
    getAttribute(k) {
      return k === 'data-lang-btn' ? lang : null;
    },
    setAttribute(k, v) {
      this.attrs[k] = v;
    },
    init() {
      this.classList._owner = this;
      return this;
    }
  }.init());
  const ruBtn = makeLangBtn('ru');
  const enBtn = makeLangBtn('en');

  const doc = {
    documentElement: { lang: 'en' },
    title: '',
    addEventListener: () => {},
    querySelector: (sel) => (sel === 'meta[name="description"]' ? metaDesc : null),
    querySelectorAll: (sel) => {
      if (sel === '[data-i18n]') return [textNode];
      if (sel === '[data-i18n-placeholder]') return [placeholderNode];
      if (sel === '[data-i18n-aria]') return [ariaNode];
      if (sel === '[data-lang-btn]') return [ruBtn, enBtn];
      return [];
    }
  };

  let copiedValue = null;
  const { HengeCore, storage } = loadHengeCore({
    document: doc,
    navigator: {
      languages: ['en-US'],
      language: 'en-US',
      clipboard: {
        writeText: async (text) => {
          copiedValue = text;
        }
      }
    }
  });

  HengeCore.setLanguage('ru');
  assert.equal(doc.documentElement.lang, 'ru');
  assert.equal(doc.title, HengeCore.I18N.ru['meta.title']);
  assert.equal(metaDesc.attrs.content, HengeCore.I18N.ru['meta.description']);
  assert.equal(textNode.textContent, HengeCore.I18N.ru['hero.title']);
  assert.equal(placeholderNode.attrs.placeholder, HengeCore.I18N.ru['demo.placeholder']);
  assert.equal(ariaNode.attrs['aria-label'], HengeCore.I18N.ru['nav.langLabel']);
  assert.equal(ruBtn.classes.has('is-active'), true);
  assert.equal(ruBtn.attrs['aria-pressed'], 'true');
  assert.equal(enBtn.classes.has('is-active'), false);
  assert.equal(enBtn.attrs['aria-pressed'], 'false');
  assert.equal(storage.get('henge_lang'), 'ru');

  const copied = await HengeCore.copyToClipboard('xattr -dr com.apple.quarantine ~/Applications/Henge.app');
  assert.equal(copied, true);
  assert.equal(copiedValue, 'xattr -dr com.apple.quarantine ~/Applications/Henge.app');

  const failClipboard = loadHengeCore({
    navigator: {
      languages: ['en-US'],
      clipboard: {
        writeText: async () => {
          throw new Error('denied');
        }
      }
    }
  });
  assert.equal(await failClipboard.HengeCore.copyToClipboard('test'), false);
});

test('HengeCore DOMContentLoaded wires demo input, Opt+X shortcut, sample chips, and copy button', async () => {
  const docListeners = new Map();
  function makeClassList(owner) {
    return {
      toggle(cls, force) {
        if (force) owner.classes.add(cls);
        else owner.classes.delete(cls);
      },
      add(...clss) {
        for (const c of clss) owner.classes.add(c);
      },
      remove(...clss) {
        for (const c of clss) owner.classes.delete(c);
      }
    };
  }
  function makeEl(extra = {}) {
    const el = {
      attrs: {},
      classes: new Set(),
      listeners: new Map(),
      textContent: '',
      value: '',
      selectionStart: 0,
      selectionEnd: 0,
      offsetWidth: 100,
      getAttribute(k) {
        return this.attrs[k] ?? null;
      },
      setAttribute(k, v) {
        this.attrs[k] = String(v);
      },
      addEventListener(type, fn) {
        this.listeners.set(type, fn);
      },
      dispatch(type, event = {}) {
        const fn = this.listeners.get(type);
        if (fn) return fn(event);
      },
      focus() {},
      setSelectionRange(s, e) {
        this.selectionStart = s;
        this.selectionEnd = e;
      },
      querySelector() {
        return null;
      },
      ...extra
    };
    el.classList = makeClassList(el);
    return el;
  }

  const demoInput = makeEl({ value: 'ghbdtn', selectionStart: 6, selectionEnd: 6 });
  const demoFixBtn = makeEl();
  const demoStatus = makeEl();
  const chip = makeEl({ attrs: { 'data-chip': 'Ghbdtn, vbh!' } });
  const copyBtn = makeEl({ attrs: { 'data-copy-text': 'xattr -dr com.apple.quarantine ~/Applications/Henge.app' } });
  let clipboardCopied = '';

  const doc = {
    documentElement: { lang: 'en' },
    title: '',
    activeElement: demoInput,
    addEventListener(type, fn) {
      docListeners.set(type, fn);
    },
    querySelector(sel) {
      if (sel === '#demo-input') return demoInput;
      if (sel === '#demo-fix-btn') return demoFixBtn;
      if (sel === '#demo-status') return demoStatus;
      if (sel === '#copy-xattr-btn') return copyBtn;
      return null;
    },
    querySelectorAll(sel) {
      if (sel === '[data-chip]') return [chip];
      return [];
    }
  };

  loadHengeCore({
    document: doc,
    navigator: {
      languages: ['en-US'],
      language: 'en-US',
      clipboard: {
        writeText: async (text) => {
          clipboardCopied = text;
        }
      }
    }
  });

  const onReady = docListeners.get('DOMContentLoaded');
  assert.equal(typeof onReady, 'function');
  onReady();

  // Click Fix button on caret at end of "ghbdtn"
  demoFixBtn.dispatch('click');
  assert.equal(demoInput.value, 'привет');
  assert.equal(demoStatus.attrs['data-status-key'], 'demo.statusConverted');

  // Click sample chip -> selects sample text
  chip.dispatch('click');
  assert.equal(demoInput.value, 'Ghbdtn, vbh!');
  assert.equal(demoInput.selectionStart, 0);
  assert.equal(demoInput.selectionEnd, 'Ghbdtn, vbh!'.length);

  // Trigger Alt+X (Option+X) keydown on demoInput
  let prevented = false;
  let stopped = false;
  demoInput.dispatch('keydown', {
    altKey: true,
    metaKey: false,
    ctrlKey: false,
    shiftKey: false,
    code: 'KeyX',
    preventDefault() { prevented = true; },
    stopPropagation() { stopped = true; }
  });
  assert.equal(prevented, true);
  assert.equal(stopped, true);
  assert.equal(demoInput.value, 'Привет, мир!');

  // Click copy button
  await copyBtn.dispatch('click');
  assert.equal(clipboardCopied, 'xattr -dr com.apple.quarantine ~/Applications/Henge.app');
  assert.equal(copyBtn.classes.has('is-copied'), true);
});

test('HengeCore wires multiple [data-copy-text]/[data-copy-target] buttons independently (brew, curl, xattr)', async () => {
  const docListeners = new Map();
  function makeCopyBtn(attrs) {
    const el = {
      attrs,
      classes: new Set(),
      listeners: new Map(),
      textContent: '',
      getAttribute(k) {
        return this.attrs[k] ?? null;
      },
      addEventListener(type, fn) {
        this.listeners.set(type, fn);
      },
      dispatch(type, event = {}) {
        const fn = this.listeners.get(type);
        if (fn) return fn(event);
      },
      querySelector() {
        return null;
      }
    };
    el.classList = {
      add(c) { el.classes.add(c); },
      remove(c) { el.classes.delete(c); }
    };
    return el;
  }

  const brewBtn = makeCopyBtn({
    'data-copy-text': 'brew tap 413d/henge https://github.com/413d/henge && brew install --cask 413d/henge/henge'
  });
  const curlBtn = makeCopyBtn({
    'data-copy-text': 'curl -fsSL https://raw.githubusercontent.com/413d/henge/main/scripts/install.sh | bash'
  });
  const xattrBtn = makeCopyBtn({
    'data-copy-text': 'xattr -dr com.apple.quarantine ~/Applications/Henge.app'
  });

  const copiedHistory = [];
  const doc = {
    documentElement: { lang: 'en' },
    title: '',
    addEventListener(type, fn) {
      docListeners.set(type, fn);
    },
    querySelector(sel) {
      if (sel === '#copy-xattr-btn') return xattrBtn;
      return null;
    },
    querySelectorAll(sel) {
      if (sel.includes('data-copy-text')) return [brewBtn, curlBtn, xattrBtn];
      return [];
    }
  };

  loadHengeCore({
    document: doc,
    navigator: {
      languages: ['en-US'],
      language: 'en-US',
      clipboard: {
        writeText: async (text) => {
          copiedHistory.push(text);
        }
      }
    }
  });

  docListeners.get('DOMContentLoaded')();
  await brewBtn.dispatch('click');
  await curlBtn.dispatch('click');
  await xattrBtn.dispatch('click');

  assert.deepEqual(copiedHistory, [
    'brew tap 413d/henge https://github.com/413d/henge && brew install --cask 413d/henge/henge',
    'curl -fsSL https://raw.githubusercontent.com/413d/henge/main/scripts/install.sh | bash',
    'xattr -dr com.apple.quarantine ~/Applications/Henge.app'
  ]);
  assert.equal(brewBtn.classes.has('is-copied'), true);
  assert.equal(curlBtn.classes.has('is-copied'), true);
  assert.equal(xattrBtn.classes.has('is-copied'), true);
});
