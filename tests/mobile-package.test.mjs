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
