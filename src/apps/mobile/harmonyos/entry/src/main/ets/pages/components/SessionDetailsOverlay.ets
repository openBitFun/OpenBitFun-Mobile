import { SessionDetailsState } from '../state/SessionDetailsState';
import { SettingsPlacement, SettingsPlacementPolicy, SettingsSheetKind } from '../policy/SettingsPlacementPolicy';
import { AdaptiveSheetOptions } from './AdaptiveSheetOptions';
import { AdaptiveSheetContent } from './AdaptiveSheetContent';
import { SessionDetailsView } from './SessionDetailsView';
import { PAGE_BG } from './Theme';

/** A stable modal host shared by compact and wide sidebars. */
@ComponentV2
export struct SessionDetailsOverlay {
  @Param state: SessionDetailsState = new SessionDetailsState();
  @Param placement: SettingsPlacement = SettingsPlacementPolicy.compactBottom(SettingsSheetKind.SessionDetails);

  build() {
    Row() {}
      .width(0).height(0)
      .bindSheet(this.state.visible, this.Content(), this.options())
  }

  @Builder
  private Content() {
    AdaptiveSheetContent({ placement: this.placement, content: () => { this.Details(); } })
  }

  @Builder
  private Details() {
    SessionDetailsView({ session: this.state.session, onClose: () => this.state.close() })
  }

  private options(): SheetOptions {
    const options = AdaptiveSheetOptions.fromPlacement(this.placement);
    options.backgroundColor = PAGE_BG;
    options.onWillDismiss = (action: DismissSheetAction): void => {
      this.state.close();
      action.dismiss();
    };
    return options;
  }
}
