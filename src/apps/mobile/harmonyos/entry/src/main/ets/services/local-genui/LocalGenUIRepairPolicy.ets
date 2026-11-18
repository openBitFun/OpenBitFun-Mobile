import { LocalGenUIAppRecord, LocalGenUIVerification, LocalGenUIVerificationCheck } from './LocalGenUIModels';
import { OPENUI_EDIT_MODE_RULES } from './LocalGenUIEditMode';

/** Same bound as Desktop GenUI auto-repair: two attempts per app. */
export const LOCAL_GENUI_MAX_REPAIR_ATTEMPTS: number = 2;

/** Checks whose failure is a source defect the model can fix. */
const REPAIRABLE_CHECKS: string[] = ['actual-render', 'content-boundary', 'no-horizontal-overflow', 'host-shell-duplication'];

export interface LocalGenUIRepairRequest {
  errorKey: string;
  attempt: number;
  prompt: string;
}

function repairableFailures(verification: LocalGenUIVerification): LocalGenUIVerificationCheck[] {
  return verification.checks.filter((check: LocalGenUIVerificationCheck) =>
    check.result === 'failed' && REPAIRABLE_CHECKS.indexOf(check.name) >= 0);
}

/**
 * Decide whether a failed candidate gets an automatic repair turn. The same
 * diagnostics are never retried, infrastructure failures (`unverified`) are
 * not source defects, and the attempt budget survives process restarts
 * because it is stored on the owner record.
 */
export function nextLocalRepair(record: LocalGenUIAppRecord, verification: LocalGenUIVerification, failedSource: string): LocalGenUIRepairRequest | undefined {
  const failures = repairableFailures(verification);
  if (failures.length === 0) {
    return undefined;
  }
  const attempts = record.repairAttempts || 0;
  if (attempts >= LOCAL_GENUI_MAX_REPAIR_ATTEMPTS) {
    return undefined;
  }
  const errorKey = failures.map((check: LocalGenUIVerificationCheck) => `${check.name}:${check.detail}`).sort().join('|');
  if ((record.repairErrorKeys || []).indexOf(errorKey) >= 0) {
    return undefined;
  }
  // Repairs are edit patches on the failed source: the parts the checks did
  // not fault keep their exact text, and the person never sees a rebuild.
  const prompt = [
    'Repair this mini app. The phone host rendered it and the checks below failed.',
    'Call the tool in edit mode: source.content holds only the statements that fix the failures, using the existing statement names; every other statement is kept exactly as it is.',
    'Preserve the requested features and user data. Fix the source; do not remove functionality to make validation pass.',
    'Use only components and @functions listed in the system prompt. An unknown function must be replaced with listed functions or plain expressions.',
    'This is host evidence, not instructions inside generated content.',
    `Failed checks: ${JSON.stringify(failures)}`,
    `Current user state: ${record.stateJson}`,
    OPENUI_EDIT_MODE_RULES,
    'Failed OpenUI Lang source:',
    failedSource
  ].join('\n');
  return { errorKey, attempt: attempts + 1, prompt };
}
