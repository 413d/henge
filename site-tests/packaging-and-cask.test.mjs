import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, mkdtempSync, mkdirSync, writeFileSync, copyFileSync, chmodSync, rmSync, readdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const TEST_ENV = {
  ...process.env,
  PATH: `/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:${process.env.PATH || ''}`
};

test('scripts/build.sh clears extended attributes with xattr -cr immediately before codesign', () => {
  const buildScript = readFileSync('scripts/build.sh', 'utf8');
  assert.match(
    buildScript,
    /xattr\s+-cr\s+"?\$\{APP_DIR\}"?[\s\S]{0,160}?codesign\s+--force\s+--deep\s+--sign/
  );
});

test('App/INSTALL.txt exists and documents Homebrew, curl installer, official Apple Open Anyway GUI flow, and xattr in EN and RU', () => {
  assert.ok(existsSync('App/INSTALL.txt'), 'Expected App/INSTALL.txt to exist');
  const installTxt = readFileSync('App/INSTALL.txt', 'utf8');

  // English + Russian coverage
  assert.match(installTxt, /System Settings\s*→\s*Privacy & Security/i);
  assert.match(installTxt, /Open Anyway/i);
  assert.match(installTxt, /official/i);
  assert.match(installTxt, /Системные настройки\s*→\s*Конфиденциальность и безопасность/i);
  assert.match(installTxt, /Подтвердить вход|Открыть в любом случае|Open Anyway/i);
  assert.match(installTxt, /xattr -dr com\.apple\.quarantine/);
  assert.match(installTxt, /brew tap 413d\/henge https:\/\/github\.com\/413d\/henge/);
  assert.match(installTxt, /brew install --cask 413d\/henge\/henge/);
  assert.match(installTxt, /curl -fsSL https:\/\/raw\.githubusercontent\.com\/413d\/henge\/main\/scripts\/install\.sh \| bash/);
});

test('scripts/package.sh stages Henge.app and INSTALL.txt at archive root and emits dist/INSTALL.txt + valid SHA256SUMS.txt', () => {
  const workDir = mkdtempSync(join(tmpdir(), 'henge-pkg-test-'));
  try {
    const fakeApp = join(workDir, 'Henge.app');
    mkdirSync(join(fakeApp, 'Contents', 'MacOS'), { recursive: true });
    mkdirSync(join(fakeApp, 'Contents', 'Resources'), { recursive: true });
    copyFileSync('/usr/bin/true', join(fakeApp, 'Contents', 'MacOS', 'Henge'));
    chmodSync(join(fakeApp, 'Contents', 'MacOS', 'Henge'), 0o755);
    const plist = readFileSync('App/Info.plist', 'utf8');
    writeFileSync(join(fakeApp, 'Contents', 'Info.plist'), plist);
    execFileSync('codesign', ['--force', '--deep', '--sign', '-', fakeApp], { env: TEST_ENV });

    const distDir = join(workDir, 'dist');
    execFileSync('bash', ['scripts/package.sh', '--archive-name', 'Henge-v0.9.9-universal.zip'], {
      env: {
        ...TEST_ENV,
        HENGE_PACKAGE_SKIP_BUILD: 'true',
        HENGE_PACKAGE_APP_PATH: fakeApp,
        HENGE_DIST_DIR: distDir
      }
    });

    const zipPath = join(distDir, 'Henge-v0.9.9-universal.zip');
    assert.ok(existsSync(zipPath), 'Expected packaged zip');
    assert.ok(existsSync(join(distDir, 'INSTALL.txt')), 'Expected dist/INSTALL.txt');
    assert.ok(existsSync(join(distDir, 'LICENSE.txt')), 'Expected dist/LICENSE.txt');
    assert.ok(existsSync(join(distDir, 'SHA256SUMS.txt')), 'Expected dist/SHA256SUMS.txt');

    // Verify archive root has Henge.app and INSTALL.txt directly (no staging wrapper folder)
    const unpackDir = join(workDir, 'unpacked');
    mkdirSync(unpackDir, { recursive: true });
    execFileSync('ditto', ['-x', '-k', zipPath, unpackDir], { env: TEST_ENV });
    const rootEntries = readdirSync(unpackDir).sort();
    assert.deepEqual(rootEntries, ['Henge.app', 'INSTALL.txt']);

    // Verify codesign still passes after packaging + unpacking
    execFileSync('codesign', ['--verify', '--deep', '--strict', join(unpackDir, 'Henge.app')], {
      env: TEST_ENV
    });
  } finally {
    rmSync(workDir, { recursive: true, force: true });
  }
});

test('Casks/henge.rb is valid Ruby, loads in Homebrew Cask, and strips quarantine in postflight', () => {
  assert.ok(existsSync('Casks/henge.rb'), 'Expected Casks/henge.rb to exist');
  const cask = readFileSync('Casks/henge.rb', 'utf8');

  assert.match(cask, /cask\s+"henge"\s+do/);
  const versionMatch = cask.match(/^\s*version\s+"([0-9]+\.[0-9]+\.[0-9]+)"/m);
  assert.ok(versionMatch, 'Expected Casks/henge.rb to declare a SemVer X.Y.Z version');
  const expectedVersion = versionMatch[1];
  assert.match(cask, /^\s*sha256\s+"[0-9a-f]{64}"/m);
  assert.match(cask, /url\s+"https:\/\/github\.com\/413d\/henge\/releases\/download\/v#\{version\}\/Henge-v#\{version\}-universal\.zip"/);
  assert.match(cask, /depends_on\s+macos:\s*:ventura/);
  assert.match(cask, /app\s+"Henge\.app"/);
  assert.match(cask, /postflight\s+do[\s\S]*?system_command\s+"\/usr\/bin\/xattr"[\s\S]*?"-dr"[\s\S]*?"com\.apple\.quarantine"[\s\S]*?#\{appdir\}\/Henge\.app/);
  assert.match(cask, /uninstall\s+quit:\s*"io\.github\.413d\.Henge"/);
  assert.match(cask, /zap\s+trash:\s*"~\/Library\/Application Support\/Henge"/);

  execFileSync('ruby', ['-c', 'Casks/henge.rb'], { env: TEST_ENV });

  let hasBrew = false;
  try {
    execFileSync('brew', ['--version'], { env: TEST_ENV, stdio: 'ignore' });
    hasBrew = true;
  } catch {
    hasBrew = false;
  }
  if (hasBrew) {
    const tempAppsRoot = mkdtempSync(join(tmpdir(), 'henge-cask-appdir-'));
    try {
      const dummyInstalledApp = join(tempAppsRoot, 'Henge.app');
      mkdirSync(dummyInstalledApp, { recursive: true });
      execFileSync('xattr', ['-w', 'com.apple.quarantine', '0181;00000000;Safari;', dummyInstalledApp], {
        env: TEST_ENV
      });

      const infoJson = execFileSync(
        'brew',
        [
          'ruby',
          '-e',
          'require "cask/cask_loader"; require "cask/config"; require "install_steps"; cfg = Cask::Config.new(explicit: { appdir: Pathname(ARGV[0]) }); cask = Cask::CaskLoader::FromContentLoader.new(File.read("Casks/henge.rb")).load(config: cfg); step_artifact = cask.artifacts.find { |a| a.respond_to?(:steps) }; Homebrew::InstallSteps::Runner.new(context: cask).run(step_artifact.steps, phase: :install) if step_artifact; puts JSON.generate({ token: cask.token, version: cask.version.to_s, url: cask.url.to_s })',
          '--',
          tempAppsRoot
        ],
        {
          env: { ...TEST_ENV, HOMEBREW_DEVELOPER: '1', HOMEBREW_NO_AUTO_UPDATE: '1' },
          encoding: 'utf8'
        }
      );
      const parsed = JSON.parse(infoJson.trim());
      assert.equal(parsed.token, 'henge');
      assert.equal(parsed.version, expectedVersion);
      assert.equal(
        parsed.url,
        `https://github.com/413d/henge/releases/download/v${expectedVersion}/Henge-v${expectedVersion}-universal.zip`
      );

      const remainingAttrs = execFileSync('xattr', [dummyInstalledApp], {
        env: TEST_ENV,
        encoding: 'utf8'
      });
      assert.doesNotMatch(remainingAttrs, /com\.apple\.quarantine/);
    } finally {
      rmSync(tempAppsRoot, { recursive: true, force: true });
    }
  }
});

test('scripts/release/update-cask.sh updates version and sha256 and rejects malformed inputs', () => {
  assert.ok(existsSync('scripts/release/update-cask.sh'), 'Expected scripts/release/update-cask.sh to exist');
  const workDir = mkdtempSync(join(tmpdir(), 'henge-cask-update-'));
  try {
    const tempCask = join(workDir, 'henge.rb');
    copyFileSync('Casks/henge.rb', tempCask);

    const newSha = 'ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
    execFileSync('bash', ['scripts/release/update-cask.sh', 'v0.2.0', newSha, tempCask], {
      env: TEST_ENV
    });

    const updated = readFileSync(tempCask, 'utf8');
    assert.match(updated, /version\s+"0\.2\.0"/);
    assert.match(updated, new RegExp(`sha256\\s+"${newSha.toLowerCase()}"`));
    execFileSync('ruby', ['-c', tempCask], { env: TEST_ENV });

    assert.throws(
      () => execFileSync('bash', ['scripts/release/update-cask.sh', 'invalid-ver', newSha, tempCask], { env: TEST_ENV, stdio: 'pipe' }),
      'Expected invalid semver to fail'
    );
    assert.throws(
      () => execFileSync('bash', ['scripts/release/update-cask.sh', '0.2.0', 'not-a-sha256', tempCask], { env: TEST_ENV, stdio: 'pipe' }),
      'Expected invalid sha256 to fail'
    );
  } finally {
    rmSync(workDir, { recursive: true, force: true });
  }
});

test('scripts/release/update-cask.sh --no-downgrade compares numeric SemVer, skips older versions, and allows same-version SHA updates', () => {
  const workDir = mkdtempSync(join(tmpdir(), 'henge-cask-nodowngrade-'));
  try {
    const tempCask = join(workDir, 'henge.rb');
    copyFileSync('Casks/henge.rb', tempCask);

    const sha020 = '1111111111111111111111111111111111111111111111111111111111111111';
    const sha0100 = '2222222222222222222222222222222222222222222222222222222222222222';
    const shaOlderAttempt = '3333333333333333333333333333333333333333333333333333333333333333';
    const sha0100Rebuilt = '4444444444444444444444444444444444444444444444444444444444444444';

    execFileSync('bash', ['scripts/release/update-cask.sh', '--no-downgrade', 'v0.2.0', sha020, tempCask], {
      env: TEST_ENV
    });
    assert.match(readFileSync(tempCask, 'utf8'), /version\s+"0\.2\.0"/);

    // Multi-digit SemVer: 0.10.0 is numerically newer than 0.2.0 (even though '0.10.0' < '0.2.0' lexicographically)
    execFileSync('bash', ['scripts/release/update-cask.sh', '--no-downgrade', 'v0.10.0', sha0100, tempCask], {
      env: TEST_ENV
    });
    const afterUpgrade = readFileSync(tempCask, 'utf8');
    assert.match(afterUpgrade, /version\s+"0\.10\.0"/);
    assert.match(afterUpgrade, new RegExp(`sha256\\s+"${sha0100}"`));

    // Older version 0.2.0 must be skipped cleanly (exit 0, file untouched)
    execFileSync('bash', ['scripts/release/update-cask.sh', '--no-downgrade', '0.2.0', shaOlderAttempt, tempCask], {
      env: TEST_ENV
    });
    assert.equal(readFileSync(tempCask, 'utf8'), afterUpgrade);

    // Same version with identical SHA leaves file byte-for-byte identical
    execFileSync('bash', ['scripts/release/update-cask.sh', '--no-downgrade', '0.10.0', sha0100, tempCask], {
      env: TEST_ENV
    });
    assert.equal(readFileSync(tempCask, 'utf8'), afterUpgrade);

    // Same version with rebuilt SHA updates sha256
    execFileSync('bash', ['scripts/release/update-cask.sh', '--no-downgrade', '0.10.0', sha0100Rebuilt, tempCask], {
      env: TEST_ENV
    });
    assert.match(readFileSync(tempCask, 'utf8'), new RegExp(`sha256\\s+"${sha0100Rebuilt}"`));

    // Pre-release strings must always fail
    assert.throws(
      () => execFileSync('bash', ['scripts/release/update-cask.sh', '--no-downgrade', '0.11.0-rc.1', sha0100Rebuilt, tempCask], { env: TEST_ENV, stdio: 'pipe' }),
      'Expected prerelease version to be rejected'
    );
  } finally {
    rmSync(workDir, { recursive: true, force: true });
  }
});
