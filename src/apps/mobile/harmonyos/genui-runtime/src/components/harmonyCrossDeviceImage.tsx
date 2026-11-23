import { localImageUrl } from './localImageUrl';
import { useEffect, useRef, useState } from 'react';
import { useI18n } from '../local-runtime/i18n';
import type { GenUIComponentProps, GenUIImplementations } from '../genUILibrary';
import { useGenUIDeviceCapabilities, type GenUICollaborationKind, type GenUICollaborationResult } from '../genUIDeviceCapabilities';

/** Host-owned media references only; a generated URL cannot become arbitrary I/O. */
export const COLLABORATION_IMAGE_ROOT = 'https://genui-assets.openbitfun.invalid/collaboration/';
const EXERCISE_EVENT = 'genui-cross-device-exercise';
export function isCollaborationImage(value: unknown): value is string {
  return typeof value === 'string' && /^https:\/\/genui-assets\.openbitfun\.invalid\/collaboration\/local-genui%3A[^/?#]+\/[0-9a-f]{32}\.jpg$/.test(value);
}

function CrossDeviceImage({ view, emit, disabled, isStreaming }: GenUIComponentProps) {
  const { t } = useI18n('flow-chat');
  const port = useGenUIDeviceCapabilities()?.collaboration;
  const kind = (view.props.kind || 'photo') as GenUICollaborationKind;
  const value = typeof view.props.value === 'string' ? view.props.value : '';
  const [result, setResult] = useState<GenUICollaborationResult | undefined>();
  const cancel = useRef<(() => void) | undefined>();
  const emitRef = useRef(emit);
  emitRef.current = emit;
  const elementRef = useRef<HTMLElement>(null);
  useEffect(() => {
    const element = elementRef.current;
    // Probe only the existing binding; no invented image or system request.
    const exercise = () => emitRef.current('change', value);
    element?.addEventListener(EXERCISE_EVENT, exercise);
    return () => element?.removeEventListener(EXERCISE_EVENT, exercise);
  }, [value]);
  const allowed = Boolean(port?.available && !disabled && !isStreaming);
  useEffect(() => {
    setResult(undefined);
    return () => { cancel.current?.(); cancel.current = undefined; };
  }, [port, kind, disabled, isStreaming]);
  const key = (suffix: string) => t(`toolCards.generativeUI.collaboration.${suffix}`);
  const start = () => {
    if (!allowed || !port || cancel.current) return;
    setResult({ status: 'pending' });
    let terminal = false;
    const cancelRequest = port.start(kind, next => {
      setResult(next);
      if (next.status !== 'pending') { terminal = true; cancel.current = undefined; }
      if (next.status === 'completed' && isCollaborationImage(next.asset)) emitRef.current('change', next.asset);
    });
    if (!terminal) cancel.current = cancelRequest;
  };
  const status = !port ? 'unavailable' : result?.status ?? (port.available ? 'ready' : 'unavailable');
  const reason = result?.reason;
  const statusLabel = reason === 'networkUnavailable' || reason === 'networkPermission' ? reason :
    port?.mode === 'invite' && status === 'ready' ? 'inviteReady' :
    port?.mode === 'invite' && status === 'pending' ? 'invitePending' : status;
  return <section ref={elementRef} className="gen-ui-cross-device" data-cross-device-kind={kind} data-status={status}>
    <button className="pk-btn pk-btn-primary" type="button" disabled={!allowed || status === 'pending'} onClick={start}>
      {typeof view.props.label === 'string' && view.props.label ? view.props.label : key(kind)}
    </button>
    <p role="status" aria-live="polite">{key(statusLabel)}</p>
    {port && isCollaborationImage(value) && <img src={localImageUrl(value)} alt={key('image')} onError={() => { if (!cancel.current) setResult({ status: 'failed', reason: 'missingImage' }); }} />}
    <small>{key('localOnly')}</small>
  </section>;
}

export const harmonyCrossDeviceComponents: GenUIImplementations['components'] = {
  CrossDeviceImage: {
    render: CrossDeviceImage,
    inspect: element => Boolean(element.querySelector('[data-cross-device-kind]')),
    exercise: (element, event) => {
      if (event !== 'change') throw new Error('CrossDeviceImage event is unavailable');
      element.querySelector('[data-cross-device-kind]')?.dispatchEvent(new CustomEvent(EXERCISE_EVENT));
    },
  },
};
