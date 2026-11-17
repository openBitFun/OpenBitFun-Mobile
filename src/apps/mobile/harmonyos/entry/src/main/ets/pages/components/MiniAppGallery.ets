import { MobileDesignGeometry, MobileDesignTypography } from '../../generated/MobileDesignTokens';
import { MiniAppSummary } from '../../model/MiniAppModels';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { MiniAppState } from '../state/MiniAppState';
import { MiniAppGalleryPolicy } from '../policy/MiniAppGalleryPolicy';
import { CARD, INK, MUTED, LINE, SUBTLE, SHADOW_SUBTLE } from './Theme';

@ComponentV2
export struct MiniAppGallery {
  @Require @Param state: MiniAppState;
  @Param bottomInset: number = 0;
  @Event onSelect: (id: string) => void = (_id: string) => {};
  @Local viewportWidth: number = 360;
  @Local stackHeight: number = 480;

  build() {
    Column() {
      if (this.state.galleryMode === 'list') {
        this.ListView()
      } else {
        Stack({ alignContent: Alignment.Center }) {
          ForEach(this.state.apps, (app: MiniAppSummary, index: number) => {
            this.SwipeCard(app, index)
          }, (app: MiniAppSummary): string => app.id)
        }
        .width('100%').layoutWeight(1).clip(true)
        .onAreaChange((_old: Area, area: Area) => { this.stackHeight = Number(area.height); })
        .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 12 })
          .onActionEnd((event: GestureEvent) => {
            const index = MiniAppGalleryPolicy.nextIndex(this.currentIndex(), event.offsetX, this.state.apps.length);
            this.focus(index);
          }))
        Row({ space: 8 }) {
          ForEach(this.state.apps, (app: MiniAppSummary, index: number) => {
            Row().width(index === this.currentIndex() ? 24 : 8).height(8)
              .borderRadius(4).backgroundColor(index === this.currentIndex() ? INK : SUBTLE)
              .opacity(index === this.currentIndex() ? 1 : 0.4)
          }, (app: MiniAppSummary): string => app.id)
        }.justifyContent(FlexAlign.Center).padding({ top: 20, bottom: 12 })
          .accessibilityLevel('no')
        Text(RemoteI18n.t('miniapp.swipeHint')).fontSize(MobileDesignTypography.labelSmall.size)
          .fontColor(SUBTLE).margin({ bottom: this.bottomInset + 16 })
      }
    }.width('100%').height('100%')
      .onAreaChange((_old: Area, area: Area) => { this.viewportWidth = Number(area.width); })
  }

  @Builder
  private SwipeCard(app: MiniAppSummary, index: number) {
    Button({ type: ButtonType.Normal }) {
      Column() {
        Image(this.preview(app.id)).width('100%').height('65%').objectFit(ImageFit.Cover)
          .draggable(false).accessibilityLevel('no')
        Column({ space: 8 }) {
          Text(app.name).fontSize(MobileDesignTypography.titleSmall.size).fontWeight(FontWeight.Bold)
            .fontColor(INK).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(app.description).fontSize(MobileDesignTypography.bodyMedium.size).fontColor(MUTED)
            .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }.width('100%').layoutWeight(1).padding(20).justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Start)
      }.width('100%').height('100%')
    }
    .id(`miniapp-card-${app.id}`)
    .width(MiniAppGalleryPolicy.cardWidth(this.viewportWidth))
    .height(MiniAppGalleryPolicy.cardHeight(this.viewportWidth, this.stackHeight))
    .padding(0).backgroundColor(CARD).borderRadius(MobileDesignGeometry.miniappCardRadius).clip(true)
    .shadow({ radius: 16, color: SHADOW_SUBTLE, offsetY: 6 })
    .scale({ x: index === this.currentIndex() ? 1 : 0.85, y: index === this.currentIndex() ? 1 : 0.85 })
    .rotate({ angle: index === this.currentIndex() ? 0 : index < this.currentIndex() ? -5 : 5 })
    .translate({ x: (index - this.currentIndex()) * (this.viewportWidth >= 600 ? 60 : 70) })
    .opacity(index === this.currentIndex() ? 1 : Math.abs(index - this.currentIndex()) === 1 ? 0.6 : 0)
    .zIndex(index === this.currentIndex() ? 3 : 1)
    .hitTestBehavior(index === this.currentIndex() ? HitTestMode.Default : HitTestMode.None)
    .accessibilityLevel(index === this.currentIndex() ? 'yes' : 'no-hide-descendants')
    .accessibilityText(`${app.name}, ${app.description}`)
    .onClick(() => { if (index === this.currentIndex()) { this.state.galleryAppId = app.id; this.onSelect(app.id); } })
  }

  @Builder
  private ListView() {
    Grid() {
      ForEach(this.state.apps, (app: MiniAppSummary) => {
        GridItem() {
          Button({ type: ButtonType.Normal }) {
            Row() {
              Image(this.preview(app.id)).width(Math.min(MobileDesignGeometry.miniappListCoverSize, this.viewportWidth * 0.36))
                .height(MobileDesignGeometry.miniappListCoverSize).objectFit(ImageFit.Cover).draggable(false)
                .accessibilityLevel('no')
              Column({ space: 8 }) {
                Text(app.name).fontSize(MobileDesignTypography.titleSmall.size).fontWeight(FontWeight.Bold)
                  .fontColor(INK).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                Text(app.description).fontSize(MobileDesignTypography.bodyMedium.size).fontColor(MUTED)
                  .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              }.layoutWeight(1).padding(16).alignItems(HorizontalAlign.Start)
            }.width('100%')
          }.id(`miniapp-list-${app.id}`).width('100%').padding(0).backgroundColor(CARD)
            .border({ width: 1, color: LINE, radius: MobileDesignGeometry.miniappListRadius }).clip(true)
            .accessibilityText(`${app.name}, ${app.description}`)
            .onClick(() => { this.state.galleryAppId = app.id; this.onSelect(app.id); })
        }
      }, (app: MiniAppSummary): string => app.id)
      GridItem() { Row().height(this.bottomInset + 24).hitTestBehavior(HitTestMode.None) }
        .columnStart(0).columnEnd(MiniAppGalleryPolicy.columns(this.viewportWidth) - 1)
    }.width('100%').layoutWeight(1).padding({ left: 16, right: 16 })
      .columnsTemplate(MiniAppGalleryPolicy.columns(this.viewportWidth) === 2 ? '1fr 1fr' : '1fr')
      .columnsGap(MobileDesignGeometry.miniappListGap).rowsGap(MobileDesignGeometry.miniappListGap)
      .scrollBar(BarState.Off)
  }

  private currentIndex(): number {
    return Math.max(0, this.state.apps.findIndex((app: MiniAppSummary): boolean => app.id === this.state.galleryAppId));
  }

  private focus(index: number): void {
    const app = this.state.apps[index];
    if (!app) return;
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => { this.state.galleryAppId = app.id; });
  }

  private preview(id: string): Resource {
    if (id === 'builtin-gomoku') return $r('app.media.miniapp_gomoku_preview');
    if (id === 'builtin-regex-playground') return $r('app.media.miniapp_regex_preview');
    return $r('app.media.miniapp_divination_preview');
  }
}
