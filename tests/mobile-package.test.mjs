import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import path from 'node:path';
import yaml from 'yaml';
const repoRoot = process.cwd();
test('Mobile Package publishes Android assets from mobile-v tags', () => {
  const workflow = yaml.parse(
    readFileSync(path.join(repoRoot, '.github/workflows/mobile-package.yml'), 'utf8'),
  );
  assert.ok(workflow.on.push.tags.includes('mobile-v*'));
  assert.match(
    workflow.jobs.android.steps.find((step) => step.name === 'Build signed Android package').run,
    /:app:assembleRelease/,
  );
  assert.equal(workflow.jobs.publish.needs.includes('android'), true);
  assert.match(
    workflow.jobs.publish.steps.find((step) => step.name === 'Create mobile release').run,
    /gh release create/,
  );
});

import {spawnSync} from 'node:child_process';
test('mobile release versions stay synchronized', () => {
 const result = spawnSync(process.execPath, ['scripts/verify-release-version-sync.mjs'], {encoding:'utf8',windowsHide:true});
 assert.equal(result.status,0,result.stderr);
});
test('mobile release verification rejects a mismatched tag version', () => {
 const result = spawnSync(process.execPath, ['scripts/verify-release-version-sync.mjs','--mobile-version','999.0.0'], {encoding:'utf8',windowsHide:true});
 assert.notEqual(result.status,0);
 assert.match(result.stderr,/expected 999\.0\.0/);
});
