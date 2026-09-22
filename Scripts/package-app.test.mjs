import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

for (const configuration of ['debug', 'release']) {
  for (const skipBuild of [false, true]) {
    test(`package_app ${configuration}, skip build: ${skipBuild}`, (t) => {
      const root = mkdtempSync(join(tmpdir(), 'repobar-package-'));
      t.after(() => rmSync(root, { recursive: true, force: true }));
      mkdirSync(join(root, 'Scripts'));
      mkdirSync(join(root, 'bin'));
      copyFileSync(new URL('./package_app.sh', import.meta.url), join(root, 'Scripts/package_app.sh'));
      writeFileSync(join(root, 'version.env'), 'MARKETING_VERSION=0.0.0\nBUILD_NUMBER=0\n');
      const calls = join(root, 'swift-calls');
      writeFileSync(calls, '');
      writeFileSync(join(root, 'bin/swift'), '#!/bin/sh\nprintf "%s\\n" "$@" --call-- >> "$SWIFT_CALLS"\n', { mode: 0o755 });

      const result = spawnSync('/bin/bash', [join(root, 'Scripts/package_app.sh'), configuration], {
        encoding: 'utf8',
        env: { ...process.env, PATH: `${join(root, 'bin')}:${process.env.PATH}`, SWIFT_CALLS: calls, SKIP_BUILD: skipBuild ? '1' : '0' },
      });
      // Stop before bundle assembly; this fixture deliberately has no build products.
      assert.equal(result.status, 1);
      assert.equal(result.stderr.trim(), `ERROR: Build dir not found: ${root}/.build/${configuration}`);
      const architecture = configuration === 'release' ? ['--arch', 'arm64', '--arch', 'x86_64'] : [];
      const expected = skipBuild ? [] : [
        'build', '-c', configuration, ...architecture, '--call--',
        'build', '-c', configuration, ...architecture, '--product', 'repobarcli', '--call--',
      ];
      assert.equal(readFileSync(calls, 'utf8'), expected.length ? `${expected.join('\n')}\n` : '');
    });
  }
}

for (const failure of ['developer signing', 'ad-hoc signing', 'notarization']) {
  test(`package_app propagates ${failure} failure`, (t) => {
    const root = mkdtempSync(join(tmpdir(), 'repobar-package-'));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    for (const directory of ['Scripts', 'bin', '.build/debug']) mkdirSync(join(root, directory), { recursive: true });
    copyFileSync(new URL('./package_app.sh', import.meta.url), join(root, 'Scripts/package_app.sh'));
    writeFileSync(join(root, 'version.env'), 'MARKETING_VERSION=0.0.0\nBUILD_NUMBER=0\n');
    writeFileSync(join(root, '.build/debug/RepoBar'), 'fixture');
    // Stub platform tools so this never signs code or contacts Apple.
    writeFileSync(join(root, 'bin/ditto'), '#!/bin/sh\nexit 0\n', { mode: 0o755 });
    writeFileSync(join(root, 'bin/codesign'), `#!/bin/sh\nexit ${failure === 'ad-hoc signing' ? 42 : 0}\n`, { mode: 0o755 });
    writeFileSync(join(root, 'Scripts/codesign_app.sh'), '#!/bin/sh\nexit 42\n', { mode: 0o755 });
    writeFileSync(join(root, 'Scripts/notarize_app.sh'), '#!/bin/sh\nexit 42\n', { mode: 0o755 });
    const result = spawnSync('/bin/bash', [join(root, 'Scripts/package_app.sh'), 'debug'], {
      encoding: 'utf8',
      env: {
        ...process.env, PATH: `${join(root, 'bin')}:${process.env.PATH}`, SKIP_BUILD: '1',
        CODESIGN_IDENTITY: failure === 'developer signing' ? 'fixture' : '', CODE_SIGN_IDENTITY: '',
        NOTARIZE: failure === 'notarization' ? '1' : '0', NOTARY_PROFILE: 'fixture',
      },
    });
    assert.equal(result.status, 42, result.stdout + result.stderr);
  });
}
