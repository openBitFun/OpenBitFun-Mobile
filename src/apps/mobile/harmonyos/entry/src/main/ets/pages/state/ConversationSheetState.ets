import { SkillPickerViewState } from './SkillPickerViewState';
/** Transient conversation UI state; never persisted or sent to the remote host. */
export class ConversationSheetState {
  readonly skillPicker: SkillPickerViewState = new SkillPickerViewState();
  kind: string = '';
  fullText: string = '';
  turnId: string = '';
  private contextIdentity: string = '';

  synchronize(contextIdentity: string): void {
    if (this.contextIdentity !== contextIdentity) {
      this.close();
      this.contextIdentity = contextIdentity;
    }
  }

  open(contextIdentity: string, kind: string, fullText: string = '', turnId: string = ''): void {
    this.synchronize(contextIdentity);
    this.kind = kind;
    this.fullText = fullText;
    this.turnId = turnId;
  }

  close(): void {
    this.skillPicker.reset();
    this.kind = '';
    this.fullText = '';
    this.turnId = '';
  }
}
