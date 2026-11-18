import {
  Icon as CatalogIcon,
  MobileAvatar,
  MobileBadge,
  MobileBanner,
  MobileButton,
  MobileCard,
  MobileCheckbox,
  MobileComposer,
  MobileDisclosure,
  MobileFileButton,
  MobileFloatingActions,
  MobileIconButton,
  MobileLink,
  MobileListRow,
  MobileMessage,
  MobilePageHeader,
  MobileRadioGroup,
  MobileScrim,
  MobileSection,
  MobileSegmentedControl,
  MobileSelect,
  MobileSidebar,
  MobileSidebarChildRow,
  MobileSidebarEntryRow,
  MobileSidebarHeader,
  MobileSidebarSectionLabel,
  MobileSidebarSessionRow,
  MobileSidebarToolsFooter,
  MobileSidebarWorkspaceRow,
  MobileStatus,
  MobileStepper,
  MobileSwitch,
  MobileTabBar,
  MobileTag,
  MobileTextField,
  MobileTextarea,
  MobileToolbar,
} from "@openbitfun/ui/mobile";
import { useI18n } from "../i18n";
import iconGuideUrl from "../../../../docs/ICON_SYSTEM.md?url";

export function ComponentSpecimen({ name }: { name: string }) {
  const { t } = useI18n();
  switch (name) {
    case "MobileIconButton":
      return (
        <MobileIconButton
          appearance="floating"
          aria-label={t("components.preview.searchLabel")}
          icon={<CatalogIcon name="search" aria-hidden="true" />}

        />
      );
    case "MobileLink":
      return <MobileLink href={iconGuideUrl}>{t("nav.docs")}</MobileLink>;
    case "MobileButton":
      return <MobileButton size="sm">{t("components.preview.actionCardTitle")}</MobileButton>;
    case "MobileCard":
      return <MobileCard appearance="elevated">{t("components.preview.cardDescription")}</MobileCard>;
    case "MobileBadge":
      return <MobileBadge dot tone="success">{t("components.preview.notifications")}</MobileBadge>;
    case "MobileBanner":
      return <MobileBanner tone="info">{t("components.preview.fieldDescription")}</MobileBanner>;
    case "MobileComposer":
      return (
        <MobileComposer
          aria-label={t("components.preview.composerPlaceholder")}
          endActions={<MobileIconButton appearance="plain" aria-label={t("components.preview.flowChat.askUserSubmit")} icon={<CatalogIcon name="arrow-up" aria-hidden="true" />} size="sm" />}
          leading={<MobileIconButton appearance="plain" aria-label={t("components.preview.add")} icon={<CatalogIcon name="plus" aria-hidden="true" />} size="sm" />}
        >
          <span>{t("components.preview.composerPlaceholder")}</span>
        </MobileComposer>
      );
    case "MobileDisclosure":
      return <MobileDisclosure onToggle={() => undefined} open title={t("detail.loading")}>{t("components.preview.fieldDescription")}</MobileDisclosure>;
    case "MobileFileButton":
      return <MobileFileButton leading={<CatalogIcon name="plus" aria-hidden="true" />}>{t("components.preview.add")}</MobileFileButton>;
    case "MobileFloatingActions":
      return (
        <MobileFloatingActions
          leading={<MobileIconButton appearance="floating" aria-label={t("components.preview.add")} icon={<CatalogIcon name="plus" aria-hidden="true" />} />}
          trailing={<MobileIconButton appearance="floating" aria-label={t("components.preview.settings")} icon={<CatalogIcon name="gear" aria-hidden="true" />} />}
        />
      );
    case "MobileTextField":
      return (
        <MobileTextField
          aria-label={t("components.preview.searchLabel")}
          leading={<CatalogIcon name="search" aria-hidden="true" />}
          placeholder={t("components.preview.searchPlaceholder")}

        />
      );
    case "MobileListRow":
      return (
        <MobileListRow
          appearance="surface"
          label={t("components.preview.session")}
          leading={<CatalogIcon name="session" aria-hidden="true" />}
          supportingText={t("components.preview.fieldDescription")}

          trailing={<CatalogIcon name="chevron-right" aria-hidden="true" />}
        />
      );
    case "MobileMessage":
      return <MobileMessage roleType="user">{t("components.preview.cardDescription")}</MobileMessage>;
    case "MobilePageHeader":
      return <MobilePageHeader centered title={t("components.preview.session")} />;
    case "MobileScrim":
      return <MobileScrim aria-label={t("components.preview.close")} style={{ blockSize: 64, inlineSize: "100%", position: "relative" }} />;
    case "MobileSection":
      return <MobileSection title={t("components.preview.appearance")}>{t("components.preview.fieldDescription")}</MobileSection>;
    case "MobileSidebar":
      return (
        <MobileSidebar
          footer={<MobileSidebarToolsFooter leading={t("scenes.mobile.sidebar.tools")} onSettingsClick={() => undefined} onToolsClick={() => undefined} settingsLabel={t("scenes.mobile.sidebar.settings")} />}
          header={<MobileSidebarHeader brand={t("scenes.mobile.sidebar.brand")} trailing={<MobileIconButton aria-label={t("scenes.mobile.sidebar.search")} icon={<CatalogIcon name="search" aria-hidden="true" />} />} />}
          style={{ maxInlineSize: 320 }}
        >
          <MobileSidebarSectionLabel>{t("scenes.mobile.sidebar.workspace")}</MobileSidebarSectionLabel>
          <MobileSidebarWorkspaceRow expanded={false} label={t("scenes.mobile.sidebar.workspace1")} onExpandChange={() => undefined}>
            <MobileSidebarChildRow label={t("scenes.mobile.sidebar.childRemote")} />
          </MobileSidebarWorkspaceRow>
          <MobileSidebarSectionLabel>{t("scenes.mobile.sidebar.recent")}</MobileSidebarSectionLabel>
          <MobileSidebarSessionRow label={t("scenes.mobile.sidebar.session1")} status="running" time="2m" />
        </MobileSidebar>
      );
    case "MobileSidebarChildRow":
      return <MobileSidebarChildRow label={t("scenes.mobile.sidebar.childRemote")} selected />;
    case "MobileSidebarEntryRow":
      return (
        <MobileSidebarEntryRow
          icon={<CatalogIcon name="session" aria-hidden="true" />}
          label={t("scenes.mobile.sidebar.assistant")}
        />
      );
    case "MobileSidebarHeader":
      return (
        <MobileSidebarHeader
          brand={t("scenes.mobile.sidebar.brand")}
          trailing={(
            <>
              <MobileIconButton aria-label={t("scenes.mobile.sidebar.search")} icon={<CatalogIcon name="search" aria-hidden="true" />} />
              <MobileIconButton aria-label={t("scenes.mobile.sidebar.collapse")} icon={<CatalogIcon name="sidebar-left" aria-hidden="true" />} />
            </>
          )}
        />
      );
    case "MobileSidebarSectionLabel":
      return (
        <MobileSidebarSectionLabel
          action={(
            <button type="button" aria-label={t("scenes.mobile.sidebar.addWorkspace")}>
              <CatalogIcon name="plus" aria-hidden="true" />
            </button>
          )}
        >
          {t("scenes.mobile.sidebar.workspace")}
        </MobileSidebarSectionLabel>
      );
    case "MobileSidebarSessionRow":
      return <MobileSidebarSessionRow label={t("scenes.mobile.sidebar.session1")} status="running" time="2m" />;
    case "MobileSidebarToolsFooter":
      return (
        <MobileSidebarToolsFooter
          leading={t("scenes.mobile.sidebar.tools")}
          onSettingsClick={() => undefined}
          onToolsClick={() => undefined}
          settingsLabel={t("scenes.mobile.sidebar.settings")}
        />
      );
    case "MobileSidebarWorkspaceRow":
      return (
        <MobileSidebarWorkspaceRow
          expanded
          label={t("scenes.mobile.sidebar.workspace1")}
          onExpandChange={() => undefined}
        >
          <MobileSidebarChildRow label={t("scenes.mobile.sidebar.childRemote")} />
          <MobileSidebarChildRow label={t("scenes.mobile.sidebar.childLocal")} />
        </MobileSidebarWorkspaceRow>
      );
    case "MobileSegmentedControl":
      return <MobileSegmentedControl aria-label={t("components.preview.segmentedLabel")} onChange={() => undefined} options={[{ label: t("components.preview.segmentedChat"), value: "chat" }, { label: t("components.preview.segmentedAgent"), value: "agent" }]} value="chat" />;
    case "MobileStatus":
      return <MobileStatus description={t("components.preview.fieldDescription")} title={t("components.preview.cardTitle")} />;
    case "MobileTextarea":
      return <MobileTextarea aria-label={t("components.preview.composerPlaceholder")} placeholder={t("components.preview.composerPlaceholder")} readOnly />;
    case "MobileAvatar":
      return (
        <div className="specimen-row">
          <MobileAvatar name={t("components.preview.session")} status="online" />
          <MobileAvatar shape="rounded">BF</MobileAvatar>
          <MobileAvatar size="sm">UI</MobileAvatar>
        </div>
      );
    case "MobileCheckbox":
      return (
        <MobileCheckbox
          defaultChecked
          description={t("components.preview.fieldDescription")}
          label={t("components.preview.notifications")}

        />
      );
    case "MobileRadioGroup":
      return (
        <MobileRadioGroup
          appearance="surface"
          name="catalog-mobile-radio"
          options={[
            { label: t("components.preview.segmentedChat"), value: "chat" },
            { label: t("components.preview.segmentedAgent"), value: "agent" },
          ]}

          value="chat"
        />
      );
    case "MobileSelect":
      return (
        <MobileSelect
          label={t("components.preview.mobileSelectLabel")}
          options={[
            { label: "deepseek-v4-pro", value: "pro" },
            { label: "deepseek-v4-flash", value: "flash" },
          ]}
          sheetTitle={t("components.preview.mobileSelectLabel")}

          defaultValue="pro"
        />
      );
    case "MobileStepper":
      return (
        <MobileStepper
          decrementLabel={t("components.preview.mobileDecrease")}
          incrementLabel={t("components.preview.mobileIncrease")}
          label={t("components.preview.mobileStepperLabel")}
          max={5}
          min={0}
          value={3}
        />
      );
    case "MobileSwitch":
      return (
        <MobileSwitch
          defaultChecked
          description={t("components.preview.fieldDescription")}
          label={t("components.preview.notifications")}

        />
      );
    case "MobileTabBar":
      return (
        <MobileTabBar
          items={[
            { icon: <CatalogIcon name="session" aria-hidden="true" />, label: t("components.preview.segmentedChat"), value: "chat" },
            { icon: <CatalogIcon name="folder" aria-hidden="true" />, label: t("components.preview.segmentedAgent"), value: "agent" },
            { icon: <CatalogIcon name="gear" aria-hidden="true" />, label: t("components.preview.settings"), value: "settings" },
          ]}
          label={t("components.preview.segmentedLabel")}

          value="chat"
        />
      );
    case "MobileTag":
      return (
        <div className="specimen-row">
          <MobileTag selected>Design</MobileTag>
          <MobileTag>Frontend</MobileTag>
          <MobileTag size="sm">Tokens</MobileTag>
        </div>
      );
    case "MobileToolbar":
      return (
        <MobileToolbar
          leading={<MobileIconButton appearance="plain" aria-label={t("components.preview.close")} icon={<CatalogIcon name="chevron-left" aria-hidden="true" />} size="sm" />}
          trailing={<MobileIconButton appearance="plain" aria-label={t("components.preview.more")} icon={<CatalogIcon name="more" aria-hidden="true" />} size="sm" />}
        >
          {t("components.preview.mobileToolbarSelection")}
        </MobileToolbar>
      );

    default:
      return null;
  }
}
