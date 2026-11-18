import { useState } from "react";
import { MobileActionSheet, MobileButton, MobileChoiceSheet, MobileConfirmSheet, MobileSheet } from "@openbitfun/ui/mobile";
import { useI18n } from "../i18n";

export function SheetSpecimen({ name }: { name: string }) {
  const { t } = useI18n();
  const [open, setOpen] = useState(false);
  const [mode, setMode] = useState("standard");
  const close = () => setOpen(false);
  const cancelLabel = t("components.preview.modalCancel");

  return (
    <>
      <MobileButton onClick={() => setOpen(true)}>{t("components.preview.modalInteractionDemo")}</MobileButton>
      {name === "MobileActionSheet" && (
        <MobileActionSheet
          actions={[
            { id: "rename", label: t("components.preview.modalSave") },
            { id: "delete", label: t("components.preview.confirmDelete"), tone: "danger" },
          ]}
          cancelLabel={cancelLabel}
          onAction={close}
          onOpenChange={setOpen}
          open={open}
          title={t("components.preview.session")}
        />
      )}
      {name === "MobileChoiceSheet" && (
        <MobileChoiceSheet
          cancelLabel={cancelLabel}
          onOpenChange={setOpen}
          onSelect={(value) => {
            setMode(value);
            close();
          }}
          open={open}
          options={[
            { label: t("components.preview.modeMinimal"), value: "minimal" },
            { label: t("components.preview.modeStandard"), value: "standard" },
            { label: t("components.preview.modeUltimate"), value: "ultimate" },
          ]}
          selectedValue={mode}
          title={t("components.preview.selectExecutionMode")}
        />
      )}
      {name === "MobileConfirmSheet" && (
        <MobileConfirmSheet
          cancelLabel={cancelLabel}
          confirmLabel={t("components.preview.confirmDelete")}
          confirmTone="danger"
          onConfirm={close}
          onOpenChange={setOpen}
          open={open}
          title={t("components.preview.confirmTitle")}
        />
      )}
      {name === "MobileSheet" && (
        <MobileSheet
          footer={<MobileButton onClick={close}>{cancelLabel}</MobileButton>}
          onOpenChange={setOpen}
          open={open}
          title={t("components.preview.modalTitle")}
        >
          <p>{t("components.preview.fieldDescription")}</p>
        </MobileSheet>
      )}
    </>
  );
}
