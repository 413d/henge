(function (global) {
  'use strict';

  const ANSI_PAIRS = [
    ['q', 'й'], ['w', 'ц'], ['e', 'у'], ['r', 'к'], ['t', 'е'],
    ['y', 'н'], ['u', 'г'], ['i', 'ш'], ['o', 'щ'], ['p', 'з'],
    ['[', 'х'], [']', 'ъ'], ['a', 'ф'], ['s', 'ы'], ['d', 'в'],
    ['f', 'а'], ['g', 'п'], ['h', 'р'], ['j', 'о'], ['k', 'л'],
    ['l', 'д'], [';', 'ж'], ["'", 'э'], ['z', 'я'], ['x', 'ч'],
    ['c', 'с'], ['v', 'м'], ['b', 'и'], ['n', 'т'], ['m', 'ь'],
    [',', 'б'], ['.', 'ю'], ['`', 'ё'],

    ['Q', 'Й'], ['W', 'Ц'], ['E', 'У'], ['R', 'К'], ['T', 'Е'],
    ['Y', 'Н'], ['U', 'Г'], ['I', 'Ш'], ['O', 'Щ'], ['P', 'З'],
    ['{', 'Х'], ['}', 'Ъ'], ['A', 'Ф'], ['S', 'Ы'], ['D', 'В'],
    ['F', 'А'], ['G', 'П'], ['H', 'Р'], ['J', 'О'], ['K', 'Л'],
    ['L', 'Д'], [':', 'Ж'], ['"', 'Э'], ['Z', 'Я'], ['X', 'Ч'],
    ['C', 'С'], ['V', 'М'], ['B', 'И'], ['N', 'Т'], ['M', 'Ь'],
    ['<', 'Б'], ['>', 'Ю'], ['~', 'Ё']
  ];

  const EN_TO_RU = new Map();
  const RU_TO_EN = new Map();
  for (const [en, ru] of ANSI_PAIRS) {
    EN_TO_RU.set(en, ru);
    RU_TO_EN.set(ru, en);
  }

  const RE_LETTER = /^\p{L}$/u;
  const RE_NUMBER = /^\p{N}$/u;
  const RE_WHITESPACE = /^\s$/u;
  const RE_WORD_CHAR = /^[\p{L}\p{Nd}_]$/u;

  function isEnglishLetter(ch) {
    const cp = ch.codePointAt(0);
    if (cp === undefined) return false;
    return (cp >= 0x0041 && cp <= 0x005A) || (cp >= 0x0061 && cp <= 0x007A);
  }

  function isRussianLetter(ch) {
    const cp = ch.codePointAt(0);
    if (cp === undefined) return false;
    return (cp >= 0x0400 && cp <= 0x04FF) || (cp >= 0x0500 && cp <= 0x052F);
  }

  function isLetter(ch) {
    return RE_LETTER.test(ch);
  }

  function isNumber(ch) {
    return RE_NUMBER.test(ch);
  }

  function isWhitespace(ch) {
    return RE_WHITESPACE.test(ch);
  }

  function isWordChar(ch) {
    return RE_WORD_CHAR.test(ch);
  }

  function detectLayout(text) {
    let englishCount = 0;
    let russianCount = 0;

    for (const ch of String(text || '')) {
      if (isEnglishLetter(ch)) {
        englishCount += 1;
      } else if (isRussianLetter(ch)) {
        russianCount += 1;
      }
    }

    if (englishCount === 0 && russianCount === 0) {
      return { layout: null, confidence: 'neutral' };
    }
    if (englishCount > russianCount) {
      return { layout: 'en', confidence: 'clear' };
    }
    if (russianCount > englishCount) {
      return { layout: 'ru', confidence: 'clear' };
    }
    return { layout: null, confidence: 'ambiguous' };
  }

  function mapChar(ch, source, target) {
    if (source === target) return ch;
    if (isNumber(ch) || isWhitespace(ch)) return ch;
    if (source === 'en' && target === 'ru') return EN_TO_RU.get(ch) ?? null;
    if (source === 'ru' && target === 'en') return RU_TO_EN.get(ch) ?? null;
    return null;
  }

  function mapText(text, source, target) {
    if (source === target || !text) return text;

    const chars = Array.from(text);
    const out = [];

    for (let i = 0; i < chars.length; i += 1) {
      const ch = chars[i];

      if (isNumber(ch) || ch === '_' || isWhitespace(ch)) {
        out.push(ch);
        continue;
      }

      const nextIsWhitespaceOrEnd = i + 1 >= chars.length || isWhitespace(chars[i + 1]);

      if (source === 'en' && target === 'ru') {
        const isDelimiter =
          ch === ',' || ch === '.' || ch === '!' || ch === '?' || ch === ':' || ch === ';';
        if (isDelimiter && nextIsWhitespaceOrEnd) {
          out.push(ch);
          continue;
        }
      }

      if (source === 'ru' && target === 'en') {
        const isDelimiter = ch === ',' || ch === '!' || ch === '?' || ch === ':' || ch === ';';
        if (isDelimiter && nextIsWhitespaceOrEnd) {
          out.push(ch);
          continue;
        }
      }

      const mapped = mapChar(ch, source, target);
      out.push(mapped !== null ? mapped : ch);
    }

    return out.join('');
  }

  function preserveCase(original, transformed) {
    if (!original || !transformed) return transformed;
    const originalLower = original.toLowerCase();
    const originalUpper = original.toUpperCase();

    if (original === originalLower) {
      const lowered = transformed.toLowerCase();
      return Array.from(lowered)[0] ?? transformed;
    }
    if (original === originalUpper) {
      const uppered = transformed.toUpperCase();
      return Array.from(uppered)[0] ?? transformed;
    }
    return transformed;
  }

  function transformText(input) {
    const text = String(input ?? '');
    if (text.length === 0) {
      return { status: 'noOp', text, reason: 'emptyText' };
    }

    const detection = detectLayout(text);
    if (!detection.layout) {
      if (detection.confidence === 'ambiguous') {
        return { status: 'noOp', text, reason: 'ambiguousDirection' };
      }
      return { status: 'noOp', text, reason: 'neutralText' };
    }

    const sourceLayout = detection.layout;
    const targetLayout = sourceLayout === 'en' ? 'ru' : 'en';
    const mappedText = mapText(text, sourceLayout, targetLayout);

    if (mappedText === text) {
      return { status: 'noOp', text, reason: 'unchanged' };
    }

    const originalChars = Array.from(text);
    const mappedChars = Array.from(mappedText);

    if (mappedChars.length !== originalChars.length) {
      return { status: 'transformed', text: mappedText };
    }

    const resolved = [];
    for (let i = 0; i < mappedChars.length; i += 1) {
      const original = originalChars[i];
      const mapped = mappedChars[i];
      if (isLetter(original) && isLetter(mapped)) {
        resolved.push(preserveCase(original, mapped));
      } else {
        resolved.push(mapped);
      }
    }

    const finalText = resolved.join('');
    if (finalText === text) {
      return { status: 'noOp', text, reason: 'unchanged' };
    }

    return { status: 'transformed', text: finalText };
  }

  function codePointBefore(str, index) {
    if (index <= 0) return null;
    const unit = str.charCodeAt(index - 1);
    if (unit >= 0xDC00 && unit <= 0xDFFF && index >= 2) {
      const high = str.charCodeAt(index - 2);
      if (high >= 0xD800 && high <= 0xDBFF) {
        return { char: str.slice(index - 2, index), start: index - 2, end: index };
      }
    }
    return { char: str.slice(index - 1, index), start: index - 1, end: index };
  }

  function codePointAt(str, index) {
    if (index >= str.length) return null;
    const cp = str.codePointAt(index);
    const len = cp !== undefined && cp > 0xFFFF ? 2 : 1;
    return { char: str.slice(index, index + len), start: index, end: index + len };
  }

  function wordBoundaryAround(str, anchorStart, anchorEnd) {
    let start = anchorStart;
    while (start > 0) {
      const prev = codePointBefore(str, start);
      if (!prev || !isWordChar(prev.char)) break;
      start = prev.start;
    }

    let end = anchorEnd;
    while (end < str.length) {
      const next = codePointAt(str, end);
      if (!next || !isWordChar(next.char)) break;
      end = next.end;
    }

    if (start >= end) return null;
    return { text: str.slice(start, end), start, end };
  }

  function previousWord(str, offset) {
    if (offset <= 0) return null;
    let end = offset;
    while (end > 0) {
      const prev = codePointBefore(str, end);
      if (!prev) break;
      if (isWordChar(prev.char)) break;
      end = prev.start;
    }
    if (end === 0) return null;
    return wordBoundaryAround(str, end, end);
  }

  function nextWord(str, offset) {
    if (offset >= str.length) return null;
    let start = offset;
    while (start < str.length) {
      const next = codePointAt(str, start);
      if (!next) break;
      if (isWordChar(next.char)) break;
      start = next.end;
    }
    if (start >= str.length) return null;
    return wordBoundaryAround(str, start, start);
  }

  function detectWordBoundary(text, caretOffset) {
    if (!text) return null;
    const safeOffset = Math.max(0, Math.min(caretOffset, text.length));

    const current = codePointAt(text, safeOffset);
    if (current && isWordChar(current.char)) {
      return wordBoundaryAround(text, current.start, current.end);
    }

    const prev = previousWord(text, safeOffset);
    if (prev) return prev;

    return nextWord(text, safeOffset);
  }

  function fixTextAtSelection(value, selStart, selEnd) {
    const text = String(value ?? '');
    const rawStart = Number.isFinite(selStart) ? selStart : 0;
    const rawEnd = Number.isFinite(selEnd) ? selEnd : rawStart;
    let start = Math.max(0, Math.min(rawStart, text.length));
    let end = Math.max(0, Math.min(rawEnd, text.length));
    if (start > end) {
      const tmp = start;
      start = end;
      end = tmp;
    }

    if (start !== end) {
      const selected = text.slice(start, end);
      const res = transformText(selected);
      if (res.status !== 'transformed') {
        return {
          newValue: text,
          newStart: start,
          newEnd: end,
          changed: false,
          status: res.status,
          reason: res.reason
        };
      }
      const newValue = text.slice(0, start) + res.text + text.slice(end);
      return {
        newValue,
        newStart: start,
        newEnd: start + res.text.length,
        changed: true,
        status: 'transformed'
      };
    }

    const boundary = detectWordBoundary(text, start);
    if (!boundary) {
      return {
        newValue: text,
        newStart: start,
        newEnd: end,
        changed: false,
        status: 'noOp',
        reason: text.length === 0 ? 'emptyText' : 'neutralText'
      };
    }

    const res = transformText(boundary.text);
    if (res.status !== 'transformed') {
      return {
        newValue: text,
        newStart: start,
        newEnd: end,
        changed: false,
        status: res.status,
        reason: res.reason
      };
    }

    const newValue = text.slice(0, boundary.start) + res.text + text.slice(boundary.end);
    const caretPos = boundary.start + res.text.length;
    return {
      newValue,
      newStart: caretPos,
      newEnd: caretPos,
      changed: true,
      status: 'transformed'
    };
  }

  const I18N = {
    en: {
      'meta.title': 'Henge — Fix mistyped RU/EN keyboard layout in one keystroke on macOS',
      'meta.description':
        'Lightweight, 100% offline macOS menu bar utility that fixes mistyped Russian and English keyboard layout text (ghbdtn → привет) with ⌥X.',

      'nav.features': 'Features',
      'nav.privacy': 'Privacy',
      'nav.install': 'Install',
      'nav.github': 'GitHub',
      'nav.langLabel': 'Language switch',

      'hero.eyebrow': 'macOS Menu Bar Utility',
      'hero.title': 'Wrong keyboard layout, fixed in one keystroke.',
      'hero.subtitle':
        'Henge lives quietly in your macOS menu bar and turns ghbdtn into привет or руддщ into hello when you press ⌥X — without switching input sources first.',
      'hero.ctaDownload': 'Download for macOS',
      'hero.ctaGithub': 'View on GitHub',
      'hero.meta': 'macOS 13+ · Universal (Apple Silicon & Intel) · Free\u00a0&\u00a0MIT',

      'demo.windowTitle': 'Live Playground',
      'demo.menubarEnabled': 'Enabled',
      'demo.menubarShortcut': 'Shortcut: ⌥X',
      'demo.menubarAccessibility': 'Accessibility access granted',
      'demo.label': 'Try typing or selecting text below',
      'demo.placeholder':
        'Type ghbdtn, select text, or place your cursor inside a word and press ⌥X...',
      'demo.fixBtn': 'Fix Text',
      'demo.hint':
        'Press ⌥X (Alt+X) on your keyboard or click Fix Text. Converts your selection, or the word around your cursor.',
      'demo.statusReady': 'Ready — pick an example or press ⌥X',
      'demo.statusConverted': 'Converted via physical ANSI key mapping',
      'demo.statusAmbiguous': 'Ambiguous direction — equal EN and RU letters (no-op)',
      'demo.statusNoOp': 'No convertible EN/RU text found (no-op)',
      'demo.chipLabel': 'Examples:',

      'features.eyebrow': 'Capabilities',
      'features.title': 'Built to stay out of your way',
      'features.subtitle':
        'Deterministic layout conversion modeled after macOS native keymaps — no AI guessing, no background interference.',
      'features.c1Title': 'Selection or word at cursor',
      'features.c1Desc':
        'Converts your active selection first. When nothing is selected, Henge detects the word around or immediately before your caret.',
      'features.c2Title': 'Detects direction from text',
      'features.c2Desc':
        'Majority-letter detection inspects the typed characters themselves, so RU ↔ EN conversion works regardless of your current macOS input source.',
      'features.c3Title': 'Preserves case, digits, and _',
      'features.c3Desc':
        'Keeps uppercase, lowercase, title case, digits, underscores, and trailing delimiter punctuation intact — ideal for both chat and code.',
      'features.c4Title': 'Quiet menu bar utility',
      'features.c4Desc':
        'Runs with no Dock icon. Remap the shortcut, exclude terminals or IDEs, and toggle Launch at Login in Settings.',

      'privacy.eyebrow': 'Privacy & Safety',
      'privacy.title': 'Zero network calls. Zero password access.',
      'privacy.subtitle':
        'Every safety invariant is enforced in the open-source Swift codebase before a single character is read or replaced.',
      'privacy.c1Title': '100% offline & local',
      'privacy.c1Desc':
        'Henge makes zero network requests, collects no telemetry, and stores preferences locally at ~/Library/Application Support/Henge/config.json.',
      'privacy.c2Title': 'Password field immunity',
      'privacy.c2Desc':
        'Secure text fields (AXSecureTextField) are blocked at every layer — Henge never reads, copies, transforms, or logs their content.',
      'privacy.c3Title': 'Accessibility first, clipboard restored',
      'privacy.c3Desc':
        'Reads and replaces text via macOS Accessibility APIs first. When an app requires clipboard fallback, Henge snapshots and immediately restores your pasteboard.',
      'privacy.limitsTitle': 'Honest boundaries',
      'privacy.limitsItem1':
        'RU ↔ EN only: Henge converts exclusively between Russian and English keyboard layouts.',
      'privacy.limitsItem2':
        'Manual trigger only: text changes only when you press ⌥X (or click Fix Text), never silently in the background.',
      'privacy.limitsItem3':
        'Ad-hoc signed builds: after updating Henge.app to a new version, macOS asks you to re-enable Accessibility access.',

      'install.eyebrow': 'Installation',
      'install.title': 'Up and running in 3 steps',
      'install.subtitle':
        'Requires macOS 13 Ventura or later. One Universal archive supports both Apple Silicon and Intel Macs.',
      'install.s1Title': 'Download and move to Applications',
      'install.s1Desc':
        'Download Henge-v*-universal.zip from the latest GitHub Release, extract Henge.app, and move it to ~/Applications (or /Applications).',
      'install.s2Title': 'Clear Gatekeeper quarantine once',
      'install.s2Desc':
        'Public releases are ad-hoc signed without an Apple Developer ID, so clear the quarantine attribute once before opening Henge.app:',
      'install.s2Explain':
        'Why this is needed: macOS 15 Sequoia blocks unnotarized browser downloads. You can also verify SHA-256 via shasum -a 256 -c SHA256SUMS.txt or build from source.',
      'install.s2Verify': 'Verify SHA-256 checksums',
      'install.s3Title': 'Launch & grant Accessibility',
      'install.s3Desc':
        'Open Henge.app and enable it under System Settings → Privacy & Security → Accessibility so it can fix text in other apps.',
      'install.copyBtn': 'Copy',
      'install.copiedBtn': 'Copied!',

      'footer.license': 'MIT License',
      'footer.releases': 'Releases',
      'footer.issues': 'Report an Issue',
      'footer.architecture': 'Architecture',
      'footer.buildFromSource': 'Build from source',
      'footer.buildHint': 'Requires Xcode Command Line Tools on macOS 13+:'
    },
    ru: {
      'meta.title': 'Henge — Исправление ошибочной раскладки RU/EN одним нажатием на macOS',
      'meta.description':
        'Лёгкая, полностью офлайн-утилита в строке меню macOS для исправления текста, набранного не в той раскладке (ghbdtn → привет), по нажатию ⌥X.',

      'nav.features': 'Возможности',
      'nav.privacy': 'Приватность',
      'nav.install': 'Установка',
      'nav.github': 'GitHub',
      'nav.langLabel': 'Переключение языка',

      'hero.eyebrow': 'Утилита для строки меню macOS',
      'hero.title': 'Ошиблись раскладкой — исправьте одним нажатием.',
      'hero.subtitle':
        'Henge тихо живёт в строке меню macOS и превращает ghbdtn в привет или руддщ в hello по нажатию ⌥X — без предварительного переключения языка.',
      'hero.ctaDownload': 'Скачать для macOS',
      'hero.ctaGithub': 'Исходный код на GitHub',
      'hero.meta': 'macOS 13+ · Universal (Apple Silicon и Intel) · Бесплатно, MIT',

      'demo.windowTitle': 'Интерактивное демо',
      'demo.menubarEnabled': 'Включено',
      'demo.menubarShortcut': 'Сочетание: ⌥X',
      'demo.menubarAccessibility': 'Доступ Accessibility выдан',
      'demo.label': 'Попробуйте ввести или выделить текст ниже',
      'demo.placeholder':
        'Напишите ghbdtn, выделите текст или поставьте курсор в слово и нажмите ⌥X...',
      'demo.fixBtn': 'Исправить',
      'demo.hint':
        'Нажмите ⌥X (Alt+X) на клавиатуре или кнопку «Исправить». Работает с выделением или словом под курсором.',
      'demo.statusReady': 'Готово — выберите пример или нажмите ⌥X',
      'demo.statusConverted': 'Исправлено по физической карте клавиш ANSI',
      'demo.statusAmbiguous': 'Неоднозначное направление — поровну EN и RU букв (пропущено)',
      'demo.statusNoOp': 'Нет текста для конвертации EN/RU (пропущено)',
      'demo.chipLabel': 'Примеры:',

      'features.eyebrow': 'Возможности',
      'features.title': 'Создан, чтобы не мешать работе',
      'features.subtitle':
        'Детерминированное преобразование по нативной раскладке macOS — без ИИ-угадывания и фоновой автозамены.',
      'features.c1Title': 'Выделение или слово под курсором',
      'features.c1Desc':
        'Сначала исправляет выделенный фрагмент. Если ничего не выделено, Henge сам находит слово под курсором или сразу перед ним.',
      'features.c2Title': 'Определяет направление по тексту',
      'features.c2Desc':
        'Алгоритм анализирует сами символы, а не текущую системную раскладку macOS — перевод RU ↔ EN сработает, даже если вы забыли переключить язык.',
      'features.c3Title': 'Сохраняет регистр, цифры и _',
      'features.c3Desc':
        'Бережно сохраняет заглавные и строчные буквы, цифры, подчёркивания _ и конечную пунктуацию — удобно и в переписке, и в коде.',
      'features.c4Title': 'Тихая жизнь в строке меню',
      'features.c4Desc':
        'Работает без иконки в Dock. В настройках можно переназначить сочетание клавиш, исключить терминалы или IDE и включить автозапуск.',

      'privacy.eyebrow': 'Приватность и безопасность',
      'privacy.title': 'Никакой сети. Никакого доступа к паролям.',
      'privacy.subtitle':
        'Все защитные ограничения зашиты в открытом коде на Swift и проверяются до чтения или замены любого символа.',
      'privacy.c1Title': '100% офлайн и локально',
      'privacy.c1Desc':
        'Henge не делает сетевых запросов, не собирает телеметрию и хранит настройки только локально в ~/Library/Application Support/Henge/config.json.',
      'privacy.c2Title': 'Иммунитет полей паролей',
      'privacy.c2Desc':
        'Защищённые поля (AXSecureTextField) блокируются на всех уровнях: Henge никогда не читает, не копирует, не меняет и не логирует пароли.',
      'privacy.c3Title': 'Accessibility в приоритете, буфер возвращается',
      'privacy.c3Desc':
        'Сначала работает напрямую через Accessibility API. Если приложение требует фоллбэка через буфер обмена, Henge сохраняет и сразу восстанавливает его содержимое.',
      'privacy.limitsTitle': 'Честные ограничения',
      'privacy.limitsItem1':
        'Только RU ↔ EN: поддерживается исключительно пара русской и английской раскладок.',
      'privacy.limitsItem2':
        'Только по команде: текст меняется лишь при нажатии ⌥X (или «Исправить»), без фоновой автозамены.',
      'privacy.limitsItem3':
        'Ad-hoc подпись: после обновления Henge.app до новой версии macOS попросит заново отметить галочку Accessibility.',

      'install.eyebrow': 'Установка',
      'install.title': 'Запуск за 3 шага',
      'install.subtitle':
        'Требуется macOS 13 Ventura или новее. Один Universal-архив работает на Apple Silicon и Intel.',
      'install.s1Title': 'Скачайте и перенесите в «Программы»',
      'install.s1Desc':
        'Скачайте архив Henge-v*-universal.zip из последнего релиза на GitHub, распакуйте Henge.app и перенесите в ~/Applications (или /Applications).',
      'install.s2Title': 'Снимите карантин Gatekeeper один раз',
      'install.s2Desc':
        'Публичные релизы подписаны ad-hoc без Apple Developer ID, поэтому перед первым запуском выполните команду в Терминале:',
      'install.s2Explain':
        'Зачем это нужно: macOS 15 Sequoia блокирует ненотаризованные загрузки из браузера. При желании проверьте SHA-256 через shasum -a 256 -c SHA256SUMS.txt или соберите из исходников.',
      'install.s2Verify': 'Проверить контрольную сумму SHA-256',
      'install.s3Title': 'Запустите и выдайте Accessibility',
      'install.s3Desc':
        'Откройте Henge.app и включите переключатель в «Системные настройки → Конфиденциальность и безопасность → Универсальный доступ».',
      'install.copyBtn': 'Скопировать',
      'install.copiedBtn': 'Скопировано!',

      'footer.license': 'Лицензия MIT',
      'footer.releases': 'Релизы',
      'footer.issues': 'Сообщить о проблеме',
      'footer.architecture': 'Архитектура',
      'footer.buildFromSource': 'Сборка из исходников',
      'footer.buildHint': 'Требуются Xcode Command Line Tools на macOS 13+:'
    }
  };

  function resolveInitialLanguage() {
    try {
      const search = typeof location !== 'undefined' && location && typeof location.search === 'string'
        ? location.search
        : '';
      if (search) {
        const match = search.match(/(?:^\?|&)lang=(ru|en)(?:&|$)/i);
        if (match && match[1]) {
          return match[1].toLowerCase() === 'ru' ? 'ru' : 'en';
        }
      }
    } catch (_) {
      // Ignore location access errors
    }

    try {
      if (typeof localStorage !== 'undefined' && localStorage && typeof localStorage.getItem === 'function') {
        const saved = localStorage.getItem('henge_lang');
        if (saved === 'ru' || saved === 'en') {
          return saved;
        }
      }
    } catch (_) {
      // Ignore storage access errors
    }

    try {
      if (typeof navigator !== 'undefined' && navigator) {
        const list = Array.isArray(navigator.languages) && navigator.languages.length > 0
          ? navigator.languages
          : (navigator.language ? [navigator.language] : []);
        for (const item of list) {
          if (typeof item === 'string' && item.toLowerCase().startsWith('ru')) {
            return 'ru';
          }
          if (typeof item === 'string' && item.trim().length > 0) {
            return 'en';
          }
        }
      }
    } catch (_) {
      // Ignore navigator access errors
    }

    return 'en';
  }

  let activeLanguage = 'en';

  function setLanguage(lang, persist = true) {
    const normalized = lang === 'ru' ? 'ru' : 'en';
    activeLanguage = normalized;
    const dict = I18N[normalized];

    if (typeof document !== 'undefined' && document) {
      if (document.documentElement) {
        document.documentElement.lang = normalized;
      }
      if (dict['meta.title']) {
        document.title = dict['meta.title'];
      }
      if (typeof document.querySelector === 'function') {
        const metaDesc = document.querySelector('meta[name="description"]');
        if (metaDesc && typeof metaDesc.setAttribute === 'function' && dict['meta.description']) {
          metaDesc.setAttribute('content', dict['meta.description']);
        }
      }
      if (typeof document.querySelectorAll === 'function') {
        for (const el of document.querySelectorAll('[data-i18n]')) {
          const key = el.getAttribute('data-i18n');
          if (key && dict[key] !== undefined) {
            el.textContent = dict[key];
          }
        }
        for (const el of document.querySelectorAll('[data-i18n-placeholder]')) {
          const key = el.getAttribute('data-i18n-placeholder');
          if (key && dict[key] !== undefined) {
            el.setAttribute('placeholder', dict[key]);
          }
        }
        for (const el of document.querySelectorAll('[data-i18n-aria]')) {
          const key = el.getAttribute('data-i18n-aria');
          if (key && dict[key] !== undefined) {
            el.setAttribute('aria-label', dict[key]);
          }
        }
        for (const btn of document.querySelectorAll('[data-lang-btn]')) {
          const isActive = btn.getAttribute('data-lang-btn') === normalized;
          if (btn.classList && typeof btn.classList.toggle === 'function') {
            btn.classList.toggle('is-active', isActive);
          }
          if (typeof btn.setAttribute === 'function') {
            btn.setAttribute('aria-pressed', isActive ? 'true' : 'false');
          }
        }
      }

      if (typeof document.querySelector === 'function') {
        const statusEl = document.querySelector('#demo-status');
        if (statusEl && typeof statusEl.getAttribute === 'function') {
          const statusKey = statusEl.getAttribute('data-status-key');
          if (statusKey && dict[statusKey] !== undefined) {
            statusEl.textContent = dict[statusKey];
          }
        }
      }
    }

    if (persist) {
      try {
        if (typeof localStorage !== 'undefined' && localStorage && typeof localStorage.setItem === 'function') {
          localStorage.setItem('henge_lang', normalized);
        }
      } catch (_) {
        // Ignore storage access errors
      }
    }

    return normalized;
  }

  async function copyToClipboard(text) {
    const value = String(text ?? '');
    if (
      typeof navigator !== 'undefined' &&
      navigator &&
      navigator.clipboard &&
      typeof navigator.clipboard.writeText === 'function'
    ) {
      try {
        await navigator.clipboard.writeText(value);
        return true;
      } catch (_) {
        // Fallback below
      }
    }

    if (
      typeof document !== 'undefined' &&
      document &&
      typeof document.createElement === 'function' &&
      document.body
    ) {
      try {
        const textarea = document.createElement('textarea');
        textarea.value = value;
        textarea.setAttribute('readonly', '');
        textarea.style.position = 'fixed';
        textarea.style.opacity = '0';
        textarea.style.pointerEvents = 'none';
        document.body.appendChild(textarea);
        textarea.select();
        const ok = typeof document.execCommand === 'function' ? document.execCommand('copy') : false;
        document.body.removeChild(textarea);
        return Boolean(ok);
      } catch (_) {
        return false;
      }
    }

    return false;
  }

  function isEditableElement(el) {
    if (!el || typeof el.tagName !== 'string') return false;
    const tag = el.tagName.toUpperCase();
    return tag === 'INPUT' || tag === 'TEXTAREA' || Boolean(el.isContentEditable);
  }

  function isFixHotkey(event) {
    return Boolean(
      event &&
      event.altKey &&
      !event.metaKey &&
      !event.ctrlKey &&
      !event.shiftKey &&
      event.code === 'KeyX'
    );
  }

  function initInteractiveUI() {
    if (typeof document === 'undefined' || !document) return;

    setLanguage(resolveInitialLanguage(), false);

    if (typeof document.querySelectorAll === 'function') {
      for (const btn of document.querySelectorAll('[data-lang-btn]')) {
        if (typeof btn.addEventListener === 'function') {
          btn.addEventListener('click', () => {
            const target = btn.getAttribute('data-lang-btn');
            if (target === 'ru' || target === 'en') {
              setLanguage(target, true);
            }
          });
        }
      }
    }

    const demoInput = typeof document.querySelector === 'function' ? document.querySelector('#demo-input') : null;
    const demoFixBtn = typeof document.querySelector === 'function' ? document.querySelector('#demo-fix-btn') : null;
    const demoStatus = typeof document.querySelector === 'function' ? document.querySelector('#demo-status') : null;
    const chips = typeof document.querySelectorAll === 'function' ? Array.from(document.querySelectorAll('[data-chip]')) : [];

    let statusPulseTimer = null;

    function updateStatus(key, stateClass) {
      if (!demoStatus) return;
      const dict = I18N[activeLanguage] || I18N.en;
      if (dict[key] !== undefined) {
        demoStatus.textContent = dict[key];
      }
      if (typeof demoStatus.setAttribute === 'function') {
        demoStatus.setAttribute('data-status-key', key);
      }
      if (demoStatus.classList) {
        demoStatus.classList.remove('is-success', 'is-muted');
        if (stateClass) demoStatus.classList.add(stateClass);
      }
    }

    function applyDemoFix() {
      if (!demoInput) return;
      const value = demoInput.value ?? '';
      const selStart = typeof demoInput.selectionStart === 'number' ? demoInput.selectionStart : value.length;
      const selEnd = typeof demoInput.selectionEnd === 'number' ? demoInput.selectionEnd : value.length;
      const res = fixTextAtSelection(value, selStart, selEnd);

      if (demoFixBtn && demoFixBtn.classList) {
        demoFixBtn.classList.add('is-pressed');
        setTimeout(() => demoFixBtn.classList.remove('is-pressed'), 140);
      }

      if (res.changed) {
        demoInput.value = res.newValue;
        if (typeof demoInput.focus === 'function') {
          demoInput.focus();
        }
        if (typeof demoInput.setSelectionRange === 'function') {
          demoInput.setSelectionRange(res.newStart, res.newEnd);
        }
        if (demoInput.classList) {
          demoInput.classList.remove('is-converted');
          void demoInput.offsetWidth;
          demoInput.classList.add('is-converted');
          clearTimeout(statusPulseTimer);
          statusPulseTimer = setTimeout(() => demoInput.classList.remove('is-converted'), 420);
        }
        updateStatus('demo.statusConverted', 'is-success');
      } else {
        const key = res.reason === 'ambiguousDirection' ? 'demo.statusAmbiguous' : 'demo.statusNoOp';
        updateStatus(key, 'is-muted');
      }
    }

    if (demoFixBtn && typeof demoFixBtn.addEventListener === 'function') {
      demoFixBtn.addEventListener('click', applyDemoFix);
    }

    if (demoInput && typeof demoInput.addEventListener === 'function') {
      demoInput.addEventListener('keydown', (event) => {
        if (isFixHotkey(event)) {
          event.preventDefault();
          event.stopPropagation();
          applyDemoFix();
        }
      });
    }

    if (typeof document.addEventListener === 'function') {
      document.addEventListener('keydown', (event) => {
        if (!demoInput || !isFixHotkey(event)) return;
        const active = document.activeElement;
        if (active && active !== demoInput && isEditableElement(active)) {
          return;
        }
        event.preventDefault();
        applyDemoFix();
      });
    }

    for (const chip of chips) {
      if (typeof chip.addEventListener === 'function') {
        chip.addEventListener('click', () => {
          if (!demoInput) return;
          const sample = chip.getAttribute('data-chip') || chip.textContent || '';
          demoInput.value = sample;
          if (typeof demoInput.focus === 'function') {
            demoInput.focus();
          }
          if (typeof demoInput.setSelectionRange === 'function') {
            demoInput.setSelectionRange(0, sample.length);
          }
          for (const other of chips) {
            const isCurrent = other === chip;
            if (other.classList) other.classList.toggle('is-active', isCurrent);
            if (typeof other.setAttribute === 'function') {
              other.setAttribute('aria-pressed', isCurrent ? 'true' : 'false');
            }
          }
          updateStatus('demo.statusReady', null);
        });
      }
    }

    const copyBtn = typeof document.querySelector === 'function' ? document.querySelector('#copy-xattr-btn') : null;
    if (copyBtn && typeof copyBtn.addEventListener === 'function') {
      let resetTimer = null;
      copyBtn.addEventListener('click', async () => {
        const targetSel = copyBtn.getAttribute('data-copy-target');
        const targetEl = targetSel && typeof document.querySelector === 'function'
          ? document.querySelector(targetSel)
          : null;
        const command =
          copyBtn.getAttribute('data-copy-text') ||
          (targetEl ? targetEl.textContent.trim() : '') ||
          'xattr -dr com.apple.quarantine ~/Applications/Henge.app';

        const ok = await copyToClipboard(command);
        if (!ok) return;

        const labelEl =
          (typeof copyBtn.querySelector === 'function' && copyBtn.querySelector('[data-copy-label]')) || copyBtn;
        const dict = I18N[activeLanguage] || I18N.en;
        labelEl.textContent = dict['install.copiedBtn'] || 'Copied!';
        if (copyBtn.classList) copyBtn.classList.add('is-copied');

        clearTimeout(resetTimer);
        resetTimer = setTimeout(() => {
          const currentDict = I18N[activeLanguage] || I18N.en;
          labelEl.textContent = currentDict['install.copyBtn'] || 'Copy';
          if (copyBtn.classList) copyBtn.classList.remove('is-copied');
        }, 2000);
      });
    }
  }

  if (typeof document !== 'undefined' && document) {
    if (document.readyState === 'interactive' || document.readyState === 'complete') {
      initInteractiveUI();
    } else if (typeof document.addEventListener === 'function') {
      document.addEventListener('DOMContentLoaded', initInteractiveUI);
    }
  }

  const api = {
    detectLayout,
    transformText,
    fixTextAtSelection,
    setLanguage,
    resolveInitialLanguage,
    copyToClipboard,
    I18N
  };

  global.HengeCore = api;
  global.HengeDemo = api;
})(typeof window !== 'undefined' ? window : globalThis);
