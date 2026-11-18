import { useState } from "react";
import { createRoot } from "react-dom/client";
import "@openbitfun/theme-openbitfun/default.css";
import "@openbitfun/ui/mobile.css";
import { ThemeRoot, mobileComponents, type ColorScheme } from "@openbitfun/ui/mobile";
import { LocaleContext, useI18n } from "./i18n";
import { DESIGN_LAB_LOCALES, resolveFirstDesignLabLocale, resolveDesignLabLocale } from "./locale.mjs";
import { MobileSceneGallery } from "./preview/MobileSceneGallery";
import { ComponentSpecimen } from "./preview/ComponentSpecimen";
import {
  MobileConversationExample,
  MobileDisclosureExample,
  MobileFloatingActionsExample,
  MobileScrimExample,
  PhoneScreenPreview,
} from "./preview/LiveComponentExamples";
import { SheetSpecimen } from "./preview/SheetSpecimen";
import "./preview/MobileSceneGallery.css";
import "./styles.css";

function Preview({ name }: { name: string }) {
  switch (name) {
    case "MobileComposer":
    case "MobileMessage":
      return <MobileConversationExample name={name} state="expanded" />;
    case "MobileDisclosure":
      return <MobileDisclosureExample state="open" />;
    case "MobileFloatingActions":
      return <MobileFloatingActionsExample state="default" />;
    case "MobileScrim":
      return <MobileScrimExample className="lab-mobile-scrim" state="hidden" />;
    case "MobileActionSheet":
    case "MobileChoiceSheet":
    case "MobileConfirmSheet":
    case "MobileSheet":
      return <SheetSpecimen name={name} />;
    default:
      return <ComponentSpecimen name={name} />;
  }
}

function DesignLab({ locale, setLocale }: { locale: Locale; setLocale: (locale: Locale) => void }) {
  const { t } = useI18n();
  const [colorScheme, setColorScheme] = useState<ColorScheme>("light");
  const [highContrast, setHighContrast] = useState(false);
  const [componentName, setComponentName] = useState("MobileSidebar");
  const contrast = highContrast ? "high" : "standard";
  const component = mobileComponents.find(({ name }) => name === componentName);

  return (
    <ThemeRoot className="design-lab" colorScheme={colorScheme} contrast={contrast} density="touch">
      <header className="lab-header">
        <strong>OpenBitFun Mobile Design Lab</strong>
        <nav>
          <a href="#mobile-patterns">{t("scenes.mobile.label")}</a>
          <a href="#mobile">{t("lab.components")}</a>
          <a href={`${import.meta.env.BASE_URL}openbitfun-mobile-standalone.html`}>{t("lab.standalone")}</a>
        </nav>
        <div className="lab-controls">
          <label>
            {t("lab.theme")}
            <select value={colorScheme} onChange={event => setColorScheme(event.target.value === "dark" ? "dark" : "light")}>
              <option value="light">{t("lab.light")}</option>
              <option value="dark">{t("lab.dark")}</option>
            </select>
          </label>
          <label>
            <input type="checkbox" checked={highContrast} onChange={event => setHighContrast(event.target.checked)} />
            {t("lab.contrast")}
          </label>
          <LanguagePicker locale={locale} onChange={setLocale} />
        </div>
      </header>
      <main>
        <section id="mobile-patterns">
          <h1>{t("scenes.mobile.label")}</h1>
          <MobileSceneGallery colorScheme={colorScheme} contrast={contrast} density="touch" />
        </section>
        <section id="mobile">
          <label className="specimen-picker">
            {t("lab.components")}
            <select value={componentName} onChange={(event) => setComponentName(event.target.value)}>
              {mobileComponents.map(({ name }) => <option key={name} value={name}>{name}</option>)}
            </select>
          </label>
          {component && (
            <div className="specimen-layout">
              <PhoneScreenPreview key={component.name}>
                <Preview name={component.name} />
              </PhoneScreenPreview>
              <section className="specimen-info">
                <h2>{component.name}</h2>
                <p lang="en">{component.description}</p>
                <h3>{t("lab.tokenRoles")}</h3>
                <ul>{component.tokens.map(token => <li key={token}><code>{token}</code></li>)}</ul>
              </section>
            </div>
          )}
        </section>
      </main>
    </ThemeRoot>
  );
}

type Locale = typeof DESIGN_LAB_LOCALES[number];

function LanguagePicker({ onChange, locale }: { onChange: (locale: Locale) => void; locale: Locale }) {
  const { t } = useI18n();
  return (
    <label className="lab-language">
      {t("lab.language")}
      <select value={locale} onChange={(event) => {
        const next = resolveDesignLabLocale(event.target.value);
        if (next) onChange(next);
      }}>
        {DESIGN_LAB_LOCALES.map(option => <option key={option} value={option}>{option}</option>)}
      </select>
    </label>
  );
}

function App() {
  const [locale, setLocale] = useState(() => resolveFirstDesignLabLocale(navigator.languages));
  document.documentElement.lang = locale;
  return (
    <LocaleContext.Provider value={locale}>
      <DesignLab locale={locale} setLocale={setLocale} />
    </LocaleContext.Provider>
  );
}

const root = document.getElementById("root");
if (!root) throw new Error("Missing Design Lab root.");
createRoot(root).render(<App />);
