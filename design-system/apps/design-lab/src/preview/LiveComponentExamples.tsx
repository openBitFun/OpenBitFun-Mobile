import { useRef, useState, type ReactNode } from "react";
import { DesignSystemContext, defaultDesignSystemContext, Icon, MobileButton, MobileComposer, MobileDisclosure, MobileFloatingActions, MobileIconButton, MobileMessage, MobileScrim } from "@openbitfun/ui/mobile";
import { useI18n } from "../i18n";

export function MobileDisclosureExample({ state }: { state: string }) {
  const { t } = useI18n();
  const [open, setOpen] = useState(state === "open");
  return <MobileDisclosure data-openbitfun-preview-state={state === "hover" ? "hover" : undefined} disabled={state === "disabled"} onToggle={() => setOpen(value => !value)} open={open} title={t("components.preview.appearance")}>
    {t("components.preview.appearanceDescription")}
  </MobileDisclosure>;
}

export function MobileConversationExample({ name, state }: { name: string; state: string }) {
  const { t } = useI18n();
  const [expanded, setExpanded] = useState(state !== "collapsed");
  const [draft, setDraft] = useState("");
  const [sent, setSent] = useState<string[]>([]);
  return <div className="design-mobile-conversation">
    <MobileMessage roleType="system">{t("components.preview.session")}</MobileMessage>
    <MobileMessage roleType="user">{t("design.contextUser")}</MobileMessage>
    <MobileMessage roleType="assistant">{t("design.contextAssistant")}</MobileMessage>
    {name === "MobileMessage" && <MobileMessage roleType={state === "user" || state === "system" ? state : "assistant"}>{t("design.contextAfter")}</MobileMessage>}
    {sent.map((message, index) => <MobileMessage key={index} roleType="user">{message}</MobileMessage>)}
    {name === "MobileComposer" && <MobileComposer expanded={expanded} onActivate={() => setExpanded(true)} aria-label={t("components.preview.composerLabel")}
      leading={<MobileIconButton appearance="plain" aria-label={t("components.preview.add")} icon={<Icon name="plus" />} onClick={() => setExpanded(true)} />}
      startActions={expanded ? <MobileButton appearance="plain" size="sm" onClick={() => setExpanded(false)}>{t("detail.option.collapsed")}</MobileButton> : undefined}
      endActions={<MobileIconButton appearance="plain" aria-label={t("components.preview.composerSend")} icon={<Icon name="arrow-up" />}
        disabled={!draft.trim()} onClick={() => { setSent(current => [...current, draft.trim()]); setDraft(""); }} />}>
      {expanded ? <textarea aria-label={t("components.preview.composerEditorLabel")} placeholder={t("components.preview.composerPlaceholder")}
        value={draft} onChange={event => setDraft(event.target.value)} /> : <span>{draft || t("components.preview.composerPlaceholder")}</span>}
    </MobileComposer>}
  </div>;
}

export function MobileFloatingActionsExample({ state }: { state: string }) {
  const { t } = useI18n();
  const [showComposer, setShowComposer] = useState(false);
  return <div className="design-mobile-footer-example" style={{ maxWidth: state === "narrow" ? 320 : undefined, paddingBottom: state === "safe-area" ? "var(--openbitfun-space-8)" : undefined }}>
    <MobileMessage roleType="assistant">{t("design.contextAssistant")}</MobileMessage>
    {showComposer && <MobileConversationExample name="MobileComposer" state="expanded" />}
    <MobileFloatingActions leading={<MobileButton onClick={() => setShowComposer(value => !value)}>{t("components.preview.add")}</MobileButton>}
      trailing={<MobileIconButton appearance="floating" aria-label={t("components.preview.close")} icon={<Icon name="xmark" />} disabled={!showComposer} onClick={() => setShowComposer(false)} />} />
  </div>;
}

export function MobileScrimExample({ className, state }: { className?: string; state: string }) {
  const { t } = useI18n();
  const [open, setOpen] = useState(state !== "hidden");
  return <section className="design-scrim-example">
    <MobileButton onClick={() => setOpen(true)}>{t("preview.scrim")}</MobileButton>
    <p>{t("preview.scrimHint")}</p>
    <MobileScrim aria-label={t("components.preview.close")} className={className} onClick={() => setOpen(false)} visible={open} />
  </section>;
}

export function PhoneScreenPreview({ children, withThread = false }: {
  children: ReactNode;
  /** Faux conversation messages behind the specimen, for chat-surface components. */
  withThread?: boolean;
}) {
  const { t } = useI18n();
  const portalHost = useRef<HTMLDivElement>(null);
  return <div className="design-phone-frame">
    <div className="design-phone-screen">
      <div className="design-phone-status" aria-hidden="true"><span>9:41</span><span>●●●</span></div>
      {withThread && <div className="design-phone-thread">
        <MobileMessage roleType="user">{t("design.contextUser")}</MobileMessage>
        <MobileMessage roleType="assistant">{t("design.contextAssistant")}</MobileMessage>
      </div>}
      <div className="design-phone-body">
        <DesignSystemContext.Provider value={{ ...defaultDesignSystemContext, portalHost: () => portalHost.current }}>
          <div ref={portalHost} className="design-phone-portal-host">{children}</div>
        </DesignSystemContext.Provider>
      </div>
      <div className="design-phone-gesture" aria-hidden="true" />
    </div>
  </div>;
}
