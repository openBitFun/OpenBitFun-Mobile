import { SettingsPlacement, SettingsPlacementMode, SettingsPlacementPolicy } from '../policy/SettingsPlacementPolicy';
import { WindowInsetsBinding } from '../../services/WindowSystemBarService';
import { PAGE_BG } from './Theme';

/** Side sheets touch the immersive window top; other placements keep native spacing. */
@ComponentV2
export struct AdaptiveSheetContent {
  @Param placement: SettingsPlacement = SettingsPlacementPolicy.compactBottom();
  @BuilderParam content: () => void = this.EmptyContent;
  @Local insets: WindowInsetsBinding = new WindowInsetsBinding();

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context) {
      this.insets.bind(this.getUIContext(), context);
    }
  }

  aboutToDisappear(): void {
    this.insets.unbind();
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.placement.mode === SettingsPlacementMode.Side ? this.insets.top : 0 })
    .backgroundColor(PAGE_BG)
  }

  @Builder
  private EmptyContent() {
    Column() {}
  }
}
