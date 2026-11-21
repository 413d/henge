import test from 'node:test';
import assert from 'node:assert/strict';
import {
  readFileSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  writeFileSync,
  copyFileSync,
  chmodSync,
  rmSync
} from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const TEST_ENV = {
  ...process.env,
  PATH: `/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:${process.env.PATH || ''}`,
  HENGE_SKIP_STOP_RUNNING: 'true'
};

function createReleaseFixture(workDir, { tag = 'v0.9.9', bundleId = 'io.github.413d.Henge' } = {}) {
  const fakeApp = join(workDir, 'src', 'Henge.app');
  mkdirSync(join(fakeApp, 'Contents', 'MacOS'), { recursive: true });
  mkdirSync(join(fakeApp, 'Contents', 'Resources'), { recursive: true });
  copyFileSync('/usr/bin/true', join(fakeApp, 'Contents', 'MacOS', 'Henge'));
  chmodSync(join(fakeApp, 'Contents', 'MacOS', 'Henge'), 0o755);

  const plistPath = join(fakeApp, 'Contents', 'Info.plist');
  copyFileSync('App/Info.plist', plistPath);
  execFileSync('plutil', ['-replace', 'CFBundleIdentifier', '-string', bundleId, plistPath], {
    env: TEST_ENV
  });
  execFileSync('plutil', ['-replace', 'CFBundleShortVersionString', '-string', tag.replace(/^v/, ''), plistPath], {
    env: TEST_ENV
  });
  execFileSync('codesign', ['--force', '--deep', '--sign', '-', fakeApp], { env: TEST_ENV });

  const releaseRoot = join(workDir, 'releases', 'download', tag);
  mkdirSync(releaseRoot, { recursive: true });
  const archiveName = `Henge-${tag}-universal.zip`;

  execFileSync('bash', ['scripts/package.sh', '--archive-name', archiveName], {
    env: {
      ...TEST_ENV,
      HENGE_PACKAGE_SKIP_BUILD: 'true',
      HENGE_PACKAGE_APP_PATH: fakeApp,
      HENGE_DIST_DIR: releaseRoot
    }
  });

  const apiJsonPath = join(workDir, 'latest.json');
  writeFileSync(
    apiJsonPath,
    JSON.stringify({
      name: `Henge ${tag}`,
      tag_name: tag,
      draft: false,
      prerelease: false
    }, null, 2)
  );

  return {
    releaseBaseUrl: `file://${join(workDir, 'releases', 'download')}`,
    apiUrl: `file://${apiJsonPath}`,
    releaseDir: releaseRoot,
    archiveName
  };
}

test('scripts/install.sh resolves latest tag via API, verifies SHA-256 + codesign, strips quarantine, and installs cleanly', () => {
  assert.ok(existsSync('scripts/install.sh'), 'Expected scripts/install.sh to exist');
  const workDir = mkdtempSync(join(tmpdir(), 'henge-install-ok-'));
  try {
    const fixture = createReleaseFixture(workDir, { tag: 'v0.9.9' });
    const installDir = join(workDir, 'target-apps');

    const output = execFileSync('bash', ['scripts/install.sh'], {
      env: {
        ...TEST_ENV,
        HENGE_API_URL: fixture.apiUrl,
        HENGE_RELEASE_BASE_URL: fixture.releaseBaseUrl,
        HENGE_INSTALL_DIR: installDir
      },
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe']
    });

    const installedApp = join(installDir, 'Henge.app');
    assert.ok(existsSync(installedApp), 'Expected Henge.app in target install directory');
    assert.match(output, /v0\.9\.9/);
    assert.match(output, /Accessibility/);

    execFileSync('codesign', ['--verify', '--deep', '--strict', installedApp], { env: TEST_ENV });
    const attrs = execFileSync('xattr', [installedApp], { env: TEST_ENV, encoding: 'utf8' });
    assert.doesNotMatch(attrs, /com\.apple\.quarantine/);
  } finally {
    rmSync(workDir, { recursive: true, force: true });
  }
});

test('scripts/install.sh aborts before unpacking on SHA-256 mismatch and preserves existing installation', () => {
  assert.ok(existsSync('scripts/install.sh'), 'Expected scripts/install.sh to exist');
  const workDir = mkdtempSync(join(tmpdir(), 'henge-install-badsha-'));
  try {
    const fixture = createReleaseFixture(workDir, { tag: 'v0.9.9' });
    writeFileSync(
      join(fixture.releaseDir, 'SHA256SUMS.txt'),
      `0000000000000000000000000000000000000000000000000000000000000000  ${fixture.archiveName}\n`
    );

    const installDir = join(workDir, 'target-apps');
    const sentinelPath = join(installDir, 'Henge.app', 'SENTINEL.txt');
    mkdirSync(join(installDir, 'Henge.app'), { recursive: true });
    writeFileSync(sentinelPath, 'keep-me');

    assert.throws(
      () =>
        execFileSync('bash', ['scripts/install.sh'], {
          env: {
            ...TEST_ENV,
            HENGE_VERSION: 'v0.9.9',
            HENGE_RELEASE_BASE_URL: fixture.releaseBaseUrl,
            HENGE_INSTALL_DIR: installDir
          },
          stdio: ['ignore', 'pipe', 'pipe']
        }),
      (err) => {
        const stderr = err.stderr?.toString() || '';
        assert.match(stderr, /checksum|sha256|SHA-256/i);
        return true;
      }
    );

    assert.equal(readFileSync(sentinelPath, 'utf8'), 'keep-me', 'Existing app must remain untouched');
  } finally {
    rmSync(workDir, { recursive: true, force: true });
  }
});

test('scripts/install.sh rejects archives whose bundle identifier is not io.github.413d.Henge', () => {
  assert.ok(existsSync('scripts/install.sh'), 'Expected scripts/install.sh to exist');
  const workDir = mkdtempSync(join(tmpdir(), 'henge-install-badid-'));
  try {
    const fixture = createReleaseFixture(workDir, {
      tag: 'v0.9.9',
      bundleId: 'com.example.WrongApp'
    });
    const installDir = join(workDir, 'target-apps');

    assert.throws(
      () =>
        execFileSync('bash', ['scripts/install.sh'], {
          env: {
            ...TEST_ENV,
            HENGE_VERSION: 'v0.9.9',
            HENGE_RELEASE_BASE_URL: fixture.releaseBaseUrl,
            HENGE_INSTALL_DIR: installDir
          },
          stdio: ['ignore', 'pipe', 'pipe']
        }),
      (err) => {
        const stderr = err.stderr?.toString() || '';
        assert.match(stderr, /CFBundleIdentifier|bundle identifier/i);
        return true;
      }
    );

    assert.ok(!existsSync(join(installDir, 'Henge.app')), 'Spoofed bundle must not be installed');
  } finally {
    rmSync(workDir, { recursive: true, force: true });
  }
});

test('scripts/install.sh falls back to $HOME/Applications without sudo when system /Applications is not writable', () => {
  assert.ok(existsSync('scripts/install.sh'), 'Expected scripts/install.sh to exist');
  const workDir = mkdtempSync(join(tmpdir(), 'henge-install-fallback-'));
  const readOnlySystemApps = join(workDir, 'readonly-system-apps');
  mkdirSync(readOnlySystemApps, { recursive: true });
  chmodSync(readOnlySystemApps, 0o555);

  try {
    const fixture = createReleaseFixture(workDir, { tag: 'v0.9.9' });
    const fakeHome = join(workDir, 'home');
    mkdirSync(fakeHome, { recursive: true });

    const env = {
      ...TEST_ENV,
      HOME: fakeHome,
      HENGE_VERSION: 'v0.9.9',
      HENGE_RELEASE_BASE_URL: fixture.releaseBaseUrl,
      HENGE_SYSTEM_APPS_DIR: readOnlySystemApps
    };
    delete env.HENGE_INSTALL_DIR;

    execFileSync('bash', ['scripts/install.sh'], {
      env,
      stdio: ['ignore', 'pipe', 'pipe']
    });

    assert.ok(
      existsSync(join(fakeHome, 'Applications', 'Henge.app')),
      'Expected fallback installation in $HOME/Applications/Henge.app'
    );
  } finally {
    chmodSync(readOnlySystemApps, 0o755);
    rmSync(workDir, { recursive: true, force: true });
  }
});
