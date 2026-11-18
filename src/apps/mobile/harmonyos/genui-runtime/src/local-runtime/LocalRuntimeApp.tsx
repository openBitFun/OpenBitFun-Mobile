import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { calendarActionKey, GenUICalendarStatusContext, type CalendarCreateStatus } from '../genUICalendarStatus';
import GenUIApplication from '../GenUIApplication';
import type { GenUIAppDefinition, GenUIAppState } from '../genUITypes';
import type { GenUIVerification } from '../genUIVerification';
import type { GenUIOpenUIActionEvent } from '../genUIOpenUI';
import { genUIProduct } from '../genUIProduct';
import {
  displayedSource,
  initialSnapshot,
  localStateEdit,
  reduceHostMessage,
  type LocalHostMessage,
  type LocalProbeReport,
  type LocalRuntimeBuild,
  type LocalRuntimeMessage,
  type LocalRuntimeSnapshot,
} from './localRuntimeProtocol';
import { probeLocalCanvas } from './localRuntimeProbe';
import {
  GenUIDeviceCapabilitiesContext,
  type GenUIDeviceCapabilityPort,
  type GenUIGestureSubscription,
  type GenUICollaborationResult,
} from '../genUIDeviceCapabilities';

/** `$name` declarations -> owner key `name` with the JSON type of its default. */
function stateTypesOf(result: unknown): Record<string, string> {
  const declarations = (result as { stateDeclarations?: Record<string, unknown> } | null)?.stateDeclarations ?? {};
  return Object.fromEntries(Object.entries(declarations).map(([key, value]) => [
    key.startsWith('$') ? key.slice(1) : key,
    value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value,
  ]));
}

export interface LocalRuntimeBridge {
  post(message: LocalRuntimeMessage): void;
  subscribe(listener: (message: LocalHostMessage) => void): () => void;
}

/** Asynchronous capabilities are not local phase 1 capabilities. */
const unsupportedProvider = {};

export default function LocalRuntimeApp({ bridge, build }: { bridge: LocalRuntimeBridge; build: LocalRuntimeBuild }) {
  const [snapshot, setSnapshot] = useState<LocalRuntimeSnapshot>(initialSnapshot);
  const snapshotRef = useRef(snapshot);
  snapshotRef.current = snapshot;
  const [calendarStatuses, setCalendarStatuses] = useState(new Map<string, CalendarCreateStatus>());
  const calendarRef = useRef(calendarStatuses);
  const [calendarReady, setCalendarReady] = useState(false);
  const calendarRequests = useRef(new Map<string, string>());
  const calendarSerial = useRef(0);
  const [collaborationAvailability, setCollaborationAvailability] = useState({ available: false, reason: 'checking' });
  const collaborationRequests = useRef(new Map<string, (result: GenUICollaborationResult) => void>());
  const collaborationSerial = useRef(0);
  const updateCalendar = useCallback((next: Map<string, CalendarCreateStatus>) => {
    calendarRef.current = next;
    setCalendarStatuses(next);
  }, []);
  const reportRef = useRef<GenUIVerification | undefined>(undefined);
  // State declarations of the mounted source, from the OpenUI parser itself.
  const declarationsRef = useRef<Record<string, string>>({});

  const apply = useCallback((reducer: (current: LocalRuntimeSnapshot) => { snapshot: LocalRuntimeSnapshot; outbound: LocalRuntimeMessage[] }) => {
    const result = reducer(snapshotRef.current);
    snapshotRef.current = result.snapshot;
    setSnapshot(result.snapshot);
    result.outbound.forEach(message => bridge.post(message));
  }, [bridge]);

  // Gesture subscriptions by id; the host only ever sees ids and gesture names.
  const gestureSubscriptions = useRef(new Map<string, GenUIGestureSubscription>());
  const nextSubscription = useRef(0);
  const deviceCapabilities = useMemo<GenUIDeviceCapabilityPort | undefined>(() => {
    if (snapshot.mode !== 'live' || snapshot.streaming || !snapshot.identity) return undefined;
    const appId = snapshot.identity.appId;
    return {
      collaboration: {
        ...collaborationAvailability,
        start(kind, onResult) {
          const requestId = `collaboration-${++collaborationSerial.current}`;
          collaborationRequests.current.set(requestId, onResult);
          bridge.post({ type: 'collaboration', appId, sourceRevision: snapshot.sourceRevision, requestId, op: 'start', kind });
          return () => {
            if (!collaborationRequests.current.delete(requestId)) return;
            bridge.post({ type: 'collaboration', appId, sourceRevision: snapshot.sourceRevision, requestId, op: 'cancel' });
          };
        },
      },
      subscribeGesture(subscription) {
        nextSubscription.current += 1;
        const subscriptionId = `gesture-${nextSubscription.current}`;
        gestureSubscriptions.current.set(subscriptionId, subscription);
        bridge.post({ type: 'capability', appId, op: 'subscribe', subscriptionId, capability: 'gesture', gesture: subscription.gesture });
        return () => {
          gestureSubscriptions.current.delete(subscriptionId);
          bridge.post({ type: 'capability', appId, op: 'unsubscribe', subscriptionId, capability: 'gesture' });
        };
      },
      setOrientation(orientation) {
        bridge.post({ type: 'orientation', appId, sourceRevision: snapshot.sourceRevision, orientation });
      },
      haptic(kind) {
        bridge.post({ type: 'haptic', appId, kind });
      },
    };
  }, [bridge, snapshot.mode, snapshot.identity, snapshot.streaming, snapshot.sourceRevision, collaborationAvailability]);

  useEffect(() => bridge.subscribe(message => {
    if (message.type === 'init') {
      collaborationRequests.current.clear();
      setCollaborationAvailability({ available: false, reason: 'checking' });
      updateCalendar(new Map());
      calendarRequests.current.clear();
      setCalendarReady(false);
    }
    if (message.type === 'collaboration_availability' || message.type === 'collaboration_result') {
      const current = snapshotRef.current;
      if (current.mode !== 'live' || current.streaming || message.appId !== current.identity?.appId || message.sourceRevision !== current.sourceRevision) return;
      if (message.type === 'collaboration_availability') {
        setCollaborationAvailability({ available: message.available, reason: message.reason });
      } else {
        const callback = collaborationRequests.current.get(message.requestId);
        if (!callback) return;
        if (message.status !== 'pending') collaborationRequests.current.delete(message.requestId);
        callback(message);
      }
      return;
    }
    if (message.type === 'calendar_receipts' || message.type === 'calendar_result') {
      const current = snapshotRef.current;
      if (message.appId !== current.identity?.appId || message.sourceRevision !== current.sourceRevision) return;
      const next = new Map(calendarRef.current);
      if (message.type === 'calendar_receipts') {
        message.params.forEach(params => next.set(calendarActionKey(params), 'added'));
        setCalendarReady(true);
      } else {
        const key = calendarRequests.current.get(message.requestId);
        if (!key) return;
        calendarRequests.current.delete(message.requestId);
        if (message.ok) next.set(key, 'added'); else next.delete(key);
      }
      updateCalendar(next);
      return;
    }
    if (message.type === 'capability_event') {
      gestureSubscriptions.current.get(message.subscriptionId)?.onGesture();
      return;
    }
    if (message.type === 'capability_status') {
      gestureSubscriptions.current.get(message.subscriptionId)?.onStatus(message.status);
      return;
    }
    if (message.type === 'probe') {
      // Let layout settle for the latest source before measuring.
      requestAnimationFrame(() => requestAnimationFrame(() => {
        const current = snapshotRef.current;
        const report: LocalProbeReport = probeLocalCanvas(message.requestId, current, build, reportRef.current, declarationsRef.current);
        bridge.post({ type: 'probe_result', report });
      }));
      return;
    }
    apply(current => reduceHostMessage(current, message, build));
  }), [apply, bridge, build, updateCalendar]);

  useEffect(() => {
    document.documentElement.dataset.colorScheme = snapshot.scheme;
    document.documentElement.style.colorScheme = snapshot.scheme;
  }, [snapshot.scheme]);

  const identity = snapshot.identity;
  const definition = useMemo<GenUIAppDefinition | undefined>(() => identity ? {
    schemaVersion: 2,
    id: identity.appId,
    title: identity.title,
    template: identity.template,
    libraryId: identity.libraryId,
    libraryRevision: identity.libraryRevision,
    designSpec: identity.designSpec,
    source: { kind: 'openui-lang', content: displayedSource(snapshot) },
    state: {},
  } : undefined, [identity, snapshot.source, snapshot.base, snapshot.streaming]); // eslint-disable-line react-hooks/exhaustive-deps
  // Keep the owner snapshot identity stable per accepted revision; OpenUI
  // re-hydrates when the initial-state object changes.
  const initialState = useMemo<GenUIAppState>(() => snapshot.state, [snapshot.sourceRevision, snapshot.stateRevision]); // eslint-disable-line react-hooks/exhaustive-deps

  const onStateChange = useCallback((state: GenUIAppState) => {
    apply(current => localStateEdit(current, state));
  }, [apply]);
  const onAction = useCallback((event: GenUIOpenUIActionEvent) => {
    const current = snapshotRef.current;
    if (!current.identity || current.mode === 'checker' || current.streaming) return;
    if (event.type === 'CreateCalendarEvent') {
      if (!calendarReady) return;
      const key = calendarActionKey(event.params ?? {});
      if (calendarRef.current.has(key)) return;
      const requestId = `calendar-${++calendarSerial.current}`;
      calendarRequests.current.set(requestId, key);
      updateCalendar(new Map(calendarRef.current).set(key, 'pending'));
      bridge.post({ type: 'action', appId: current.identity.appId, sourceRevision: current.sourceRevision, action: event.type, message: event.humanFriendlyMessage ?? '', params: JSON.parse(key), requestId });
      return;
    }
    bridge.post({ type: 'action', appId: current.identity.appId, sourceRevision: current.sourceRevision, action: event.type, message: event.humanFriendlyMessage ?? '', params: event.params ?? {} });
  }, [bridge, calendarReady, updateCalendar]);
  const onTargetEvent = useCallback(() => undefined, []);
  const onParseResult = useCallback((result: unknown) => { declarationsRef.current = stateTypesOf(result); }, []);

  if (snapshot.status === 'waiting') return <div className="local-genui-runtime__waiting" data-local-genui-status="waiting" />;
  if (snapshot.status === 'unsupported' || !definition) {
    return <div className="local-genui-runtime__unsupported" role="alert" data-local-genui-status="unsupported">{snapshot.reason ?? 'unsupported'}</div>;
  }
  return <div className="local-genui-runtime" data-local-genui-status="ready" data-local-genui-mode={snapshot.mode}>
    <GenUICalendarStatusContext.Provider value={{ ready: calendarReady, statuses: calendarStatuses }}>
    <GenUIDeviceCapabilitiesContext.Provider value={deviceCapabilities}>
    <GenUIApplication
      key={`${definition.id}:${snapshot.sourceRevision}`}
      product={genUIProduct}
      definition={definition}
      initialState={initialState}
      streaming={snapshot.streaming}
      readOnly={snapshot.mode === 'checker'}
      persistState={snapshot.mode === 'live'}
      onStateChange={onStateChange}
      onAction={onAction}
      asyncProvider={unsupportedProvider}
      asyncTarget="unsupported"
      onTargetEvent={onTargetEvent}
      onVerification={report => { reportRef.current = report; }}
      onParseResult={onParseResult}
      hostShell="native"
    />
    </GenUIDeviceCapabilitiesContext.Provider>
    </GenUICalendarStatusContext.Provider>
  </div>;
}
