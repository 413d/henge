import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function readPngDimensions(filePath) {
  const buf = fs.readFileSync(filePath);
  assert.ok(buf.length >= 24, `${filePath} is too small to be a valid PNG`);
  assert.deepEqual(buf.subarray(0, 8), PNG_SIGNATURE, `${filePath} does not have a valid PNG signature`);
  assert.equal(buf.subarray(12, 16).toString('ascii'), 'IHDR', `${filePath} missing IHDR chunk`);
  return {
    width: buf.readUInt32BE(16),
    height: buf.readUInt32BE(20)
  };
}

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
    const { width, height } = readPngDimensions(f.path);
    assert.equal(width, f.w, `${f.path} width mismatch`);
    assert.equal(height, f.h, `${f.path} height mismatch`);
  }
});
