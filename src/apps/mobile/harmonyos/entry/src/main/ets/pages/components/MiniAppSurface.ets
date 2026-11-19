import { MobileDesignGeometry, MobileDesignTypography } from '../../generated/MobileDesignTokens';
import { MiniAppActions, emptyMiniAppActions } from '../../model/MiniAppModels';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { MiniAppState } from '../state/MiniAppState';
import { LocalGenUIGalleryEntry } from '../../services/local-genui/LocalGenUIModels';
import { MiniAppGallery } from './MiniAppGallery';
import { TemplateIcon } from './TemplateIcon';
import { MiniAppWebView } from './MiniAppWebView';
import { NavigationBackButton } from './NavigationBackButton';
import { PAGE_BG, INK, MUTED, SOFT, TRANSPARENT } from './Theme';
import { WindowInsetsBinding } from '../../services/WindowSystemBarService';

@ComponentV2
export struct MiniAppSurface {
  @Param state: MiniAppState = new MiniAppState();
  @Param actions: MiniAppActions = emptyMiniAppActions();
  /** Generated apps the user added to the gallery (Local GenUI Mode). */
  @Param generatedApps: LocalGenUIGalleryEntry[] = [];
  @Event onOpenGenerated: (appId: string) => void = (_appId: string) => {};
  @Event onRemoveGenerated: (appId: string) => void = (_appId: string) => {};
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
      // The gallery is a full-screen surface, so its header band owns the top
      // edge of the window: the box grows by the status bar strip and the
      // controls keep the 56 the design gives them below it, instead of sitting
      // under the clock and the indicators. The band spans the window
      // horizontally, so it reserves the side strips too — a rotated device puts
      // the camera cutout on the back control's edge.
      this.Header()
      if (this.state.document) {
        MiniAppWebView({ document: this.state.document, revision: this.state.revision, request: this.actions.request })
          .layoutWeight(1)
      } else {
        Column() {
          if (this.state.loading) {
            LoadingProgress().width(32).height(32).margin(24)
          } else if (this.state.error) {
            Text(this.state.error).fontSize(MobileDesignTypography.bodyMedium.size)
              .fontColor(MUTED).padding({ top: 16, bottom: 16 }).copyOption(CopyOptions.InApp)
            Button(RemoteI18n.t('miniapp.refresh'))
              .fontColor(INK).backgroundColor(SOFT).onClick(() => this.actions.refresh())
          } else if (this.state.apps.length === 0 && this.generatedApps.length === 0) {
            Text(RemoteI18n.t('miniapp.empty')).fontSize(MobileDesignTypography.bodyMedium.size)
              .fontColor(MUTED).padding(24)
          } else {
            MiniAppGallery({
              state: this.state,
              bottomInset: this.insets.bottom,
              onSelect: this.actions.select,
              generatedApps: this.generatedApps,
              onOpenGenerated: this.onOpenGenerated,
              onRemoveGenerated: this.onRemoveGenerated
            })
              .layoutWeight(1)
          }
        }.width('100%').constraintSize({ maxWidth: 1000 }).layoutWeight(1)
          // Each gallery mode owns its bottom safe-area clearance.
          .alignItems(HorizontalAlign.Start)
      }
    }.width('100%').height('100%').backgroundColor(PAGE_BG)
  }

  @Builder
  private Header() {
      Row({ space: 8 }) {
        NavigationBackButton({ onBack: (): void => {
          if (this.state.appId) this.actions.back();
          else this.actions.close();
        } })
        Text(this.state.appId ? this.state.name : RemoteI18n.t('miniapp.title'))
          .fontSize(MobileDesignTypography.bodyLarge.size).fontWeight(FontWeight.Medium)
          .fontColor(INK).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center).layoutWeight(1)
        if (!this.state.appId) {
          Button({ type: ButtonType.Normal }) {
            Stack({ alignContent: Alignment.Center }) {
              TemplateIcon({ src: this.state.galleryMode === 'cards' ? $r('app.media.miniapp_view_list') :
                $r('app.media.miniapp_view_cards'), iconWidth: 18, iconHeight: 18, tint: MUTED })
            }.width(MobileDesignGeometry.miniappViewToggleSurfaceSize)
              .height(MobileDesignGeometry.miniappViewToggleSurfaceSize)
              .backgroundColor(SOFT).borderRadius(10)
              .hitTestBehavior(HitTestMode.None)
          }.id('miniapp-view-toggle').width(48).height(48).padding(0)
            .backgroundColor(TRANSPARENT).borderRadius(10)
            .accessibilityText(RemoteI18n.t(this.state.galleryMode === 'cards' ? 'miniapp.showList' : 'miniapp.showCards'))
            .onClick(() => { this.state.galleryMode = this.state.galleryMode === 'cards' ? 'list' : 'cards'; })
        } else { Blank().width(48) }
      }.width('100%').height(56 + this.insets.top)
        .padding({ left: this.insets.leftPadding(12), right: this.insets.rightPadding(12), top: this.insets.top })
  }

}
