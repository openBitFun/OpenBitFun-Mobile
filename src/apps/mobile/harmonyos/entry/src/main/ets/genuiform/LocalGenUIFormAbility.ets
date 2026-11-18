import { Want } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LocalGenUIDesktopCardStore } from '../services/local-genui/LocalGenUIDesktopCardStore';
import {
  FORM_IDENTITY_PARAM,
  LocalGenUIDesktopCards
} from '../services/local-genui/LocalGenUIDesktopCards';

const DOMAIN = 0x0000;
const TAG = 'OpenBitFunGenUICard';

/**
 * Card host of generated-app desktop cards. It runs in its own process and
 * only reads and writes the shared card files; it never opens the Local GenUI
 * database, model provider, or runtime. The UI process owns app content and
 * pushes it with `formProvider.updateForm`.
 */
export default class LocalGenUIFormAbility extends FormExtensionAbility {
  private store(): LocalGenUIDesktopCardStore {
    return new LocalGenUIDesktopCardStore(this.context.filesDir);
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    const parameters = want.parameters as Record<string, Object> | undefined;
    const formIdValue = parameters ? parameters[FORM_IDENTITY_PARAM] : undefined;
    const formId = typeof formIdValue === 'string' ? formIdValue : '';
    const store = this.store();
    // The launcher may forward the app id; otherwise the app staged it when
    // its "Add to desktop" menu opened. The add callback binds again when the
    // launcher calls it.
    const forwarded = LocalGenUIDesktopCards.appIdOfAddWant(parameters);
    const appId = forwarded.length > 0 ? forwarded : store.claimPendingAdd();
    if (forwarded.length > 0) {
      store.claimPendingAdd();
    }
    if (formId.length > 0 && appId.length > 0) {
      store.bind(formId, appId);
    }
    hilog.info(DOMAIN, TAG, 'Card added bound=%{public}s source=%{public}s', String(appId.length > 0),
      forwarded.length > 0 ? 'want' : (appId.length > 0 ? 'pending' : 'none'));
    if (formId.length > 0) {
      // The preview needs a file descriptor that must outlive this call.
      setTimeout(() => { void store.refresh(formId); }, 0);
    }
    return formBindingData.createFormBindingData(store.textData(formId));
  }

  onUpdateForm(formId: string): void {
    void this.store().refresh(formId);
  }

  onCastToNormalForm(formId: string): void {
    void this.store().refresh(formId);
  }

  onChangeFormVisibility(_newStatus: Record<string, number>): void {
  }

  onFormEvent(_formId: string, _message: string): void {
  }

  onRemoveForm(formId: string): void {
    this.store().unbind(formId);
    hilog.info(DOMAIN, TAG, '%{public}s', 'Card removed');
  }
}
