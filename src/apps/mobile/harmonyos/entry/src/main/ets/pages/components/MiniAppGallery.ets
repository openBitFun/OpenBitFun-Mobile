import { AddFormMenuItem } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { LocalGenUIState } from '../state/LocalGenUIState';
import { LocalGenUIGalleryEntry } from '../../services/local-genui/LocalGenUIModels';
import { MobileDesignGeometry, MobileDesignTypography } from '../../generated/MobileDesignTokens';
import { MiniAppSummary } from '../../model/MiniAppModels';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { MiniAppState } from '../state/MiniAppState';
import { MiniAppGalleryPolicy } from '../policy/MiniAppGalleryPolicy';
import { CARD, INK, MUTED, LINE, SUBTLE, SHADOW_SUBTLE, CONNECT_HERO_ACCENT, CONNECT_HERO_SURFACE, TRANSPARENT } from './Theme';

interface MiniAppGalleryItem extends MiniAppSummary {
  generatedId: string;
  thumbnailPath: string;
}

@ComponentV2
export struct MiniAppGallery {
  @Require @Param state: MiniAppState;
  @Param bottomInset: number = 0;
  @Event onSelect: (id: string) => void = (_id: string) => {};
  @Param generatedApps: LocalGenUIGalleryEntry[] = [];
  @Param generatedState: LocalGenUIState = new LocalGenUIState();
  @Event onOpenGenerated: (id: string) => void = (_id: string) => {};
  @Event onRemoveGenerated: (id: string) => void = (_id: string) => {};
  @Event onPrepareDesktopCard: (id: string) => void = (_id: string) => {};
  @Event onDesktopCardAdded: (id: string, formId: string, error: string) => void =
    (_id: string, _formId: string, _error: string) => {};
  @Local failedThumbnails: string[] = [];
  @Local viewportWidth: number = 360;
  @Local stackHeight: number = 480;

  build() {
    Column() {
      if (this.state.galleryMode === 'list') {
        this.ListView()
      } else {
        Stack({ alignContent: Alignment.Center }) {
          ForEach(this.items(), (app: MiniAppGalleryItem, index: number) => {
            this.SwipeCard(app, index)
          }, (app: MiniAppGalleryItem): string => app.id)
        }
        .width('100%').layoutWeight(1).clip(true)
        .onAreaChange((_old: Area, area: Area) => { this.stackHeight = Number(area.height); })
        .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 12 })
          .onActionEnd((event: GestureEvent) => {
            const index = MiniAppGalleryPolicy.nextIndex(this.currentIndex(), event.offsetX, this.items().length);
            this.focus(index);
          }))
        Row({ space: 8 }) {
          ForEach(this.items(), (app: MiniAppGalleryItem, index: number) => {
            Row().width(index === this.currentIndex() ? 24 : 8).height(8)
              .borderRadius(4).backgroundColor(index === this.currentIndex() ? INK : SUBTLE)
              .opacity(index === this.currentIndex() ? 1 : 0.4)
          }, (app: MiniAppGalleryItem): string => app.id)
        }.justifyContent(FlexAlign.Center).padding({ top: 20, bottom: 12 })
          .accessibilityLevel('no')
        Text(RemoteI18n.t('miniapp.swipeHint')).fontSize(MobileDesignTypography.labelSmall.size)
          .fontColor(SUBTLE).margin({ bottom: this.bottomInset + 16 })
      }
    }.width('100%').height('100%')
      .onAreaChange((_old: Area, area: Area) => { this.viewportWidth = Number(area.width); })
  }

  @Builder
  private SwipeCard(app: MiniAppGalleryItem, index: number) {
    Button({ type: ButtonType.Normal }) {
      Column() {
        this.Cover(app, '100%', '65%')
        Column({ space: 8 }) {
          Text(app.name).fontSize(MobileDesignTypography.titleSmall.size).fontWeight(FontWeight.Bold)
            .fontColor(INK).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(app.description).fontSize(MobileDesignTypography.bodyMedium.size).fontColor(MUTED)
            .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }.width('100%').layoutWeight(1).padding(20).justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Start)
      }.width('100%').height('100%')
    }
    .id(this.elementId(app, true))
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
    .onClick(() => { if (index === this.currentIndex()) this.select(app); })
    .bindContextMenu(this.GeneratedActions(app, true), ResponseType.LongPress, {
      onAppear: () => {
        if (app.generatedId.length > 0) this.onPrepareDesktopCard(app.generatedId);
      }
    })
  }

  @Builder
  private ListView() {
    Grid() {
      ForEach(this.items(), (app: MiniAppGalleryItem) => {
        GridItem() {
          Button({ type: ButtonType.Normal }) {
            Row() {
              this.Cover(app, Math.min(MobileDesignGeometry.miniappListCoverSize, this.viewportWidth * 0.36),
                MobileDesignGeometry.miniappListCoverSize)
              Column({ space: 8 }) {
                Text(app.name).fontSize(MobileDesignTypography.titleSmall.size).fontWeight(FontWeight.Bold)
                  .fontColor(INK).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                Text(app.description).fontSize(MobileDesignTypography.bodyMedium.size).fontColor(MUTED)
                  .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              }.layoutWeight(1).padding(16).alignItems(HorizontalAlign.Start)
            }.width('100%')
          }.id(this.elementId(app, false)).width('100%').padding(0).backgroundColor(CARD)
            .border({ width: 1, color: LINE, radius: MobileDesignGeometry.miniappListRadius }).clip(true)
            .accessibilityText(`${app.name}, ${app.description}`)
            .onClick(() => this.select(app))
            .bindContextMenu(this.GeneratedActions(app, false), ResponseType.LongPress, {
              onAppear: () => {
                if (app.generatedId.length > 0) this.onPrepareDesktopCard(app.generatedId);
              }
            })
        }
      }, (app: MiniAppGalleryItem): string => app.id)
      GridItem() { Row().height(this.bottomInset + 24).hitTestBehavior(HitTestMode.None) }
        .columnStart(0).columnEnd(MiniAppGalleryPolicy.columns(this.viewportWidth) - 1)
    }.width('100%').layoutWeight(1).padding({ left: 16, right: 16 })
      .columnsTemplate(MiniAppGalleryPolicy.columns(this.viewportWidth) === 2 ? '1fr 1fr' : '1fr')
      .columnsGap(MobileDesignGeometry.miniappListGap).rowsGap(MobileDesignGeometry.miniappListGap)
      .scrollBar(BarState.Off)
  }

  @Builder
  private Cover(app: MiniAppGalleryItem, width: Length, height: Length) {
    Stack() {
      if (app.generatedId.length === 0) {
        Image(this.preview(app.id)).width('100%').height('100%').objectFit(ImageFit.Cover)
          .draggable(false).accessibilityLevel('no')
      } else if (app.thumbnailPath.length > 0 && !this.failedThumbnails.includes(app.thumbnailPath)) {
        Image(`file://${app.thumbnailPath}`).width('100%').height('100%').objectFit(ImageFit.Contain)
          .draggable(false).accessibilityLevel('no')
          .onError(() => { this.failedThumbnails = this.failedThumbnails.concat([app.thumbnailPath]); })
      } else {
        SymbolGlyph($r('sys.symbol.square_grid_2x2'))
          .fontSize(30).fontColor([CONNECT_HERO_ACCENT]).accessibilityLevel('no')
      }
    }
    .width(width).height(height).clip(true)
    .backgroundColor(app.generatedId.length > 0 ? CONNECT_HERO_SURFACE : TRANSPARENT)
  }

  @Builder
  private GeneratedActions(app: MiniAppGalleryItem, card: boolean) {
    if (app.generatedId.length > 0) {
      Menu() {
        if (this.generatedState.canAddToDesktop(app.generatedId)) {
          AddFormMenuItem(this.generatedState.desktopCardWant(app.generatedId), this.elementId(app, card), {
            formBindingData: this.generatedState.desktopCardInitialData(app.generatedId, app.name),
            style: { options: { content: RemoteI18n.t('localGenui.addToDesktop') } },
            callback: (error: BusinessError, formId: string) => {
              this.onDesktopCardAdded(app.generatedId, formId ?? '', error && error.code ? `${error.code}` : '');
            }
          })
        }
        MenuItem({ content: RemoteI18n.t('localGenui.removeFromGallery') })
          .onClick(() => this.onRemoveGenerated(app.generatedId))
      }
    }
  }

  private items(): MiniAppGalleryItem[] {
    const builtins = this.state.apps.map((app: MiniAppSummary): MiniAppGalleryItem => ({
      id: app.id, name: app.name, description: app.description, generatedId: '', thumbnailPath: ''
    }));
    const generated = this.generatedApps.map((entry: LocalGenUIGalleryEntry): MiniAppGalleryItem => ({
      id: `generated:${entry.appId}`,
      name: entry.title,
      description: RemoteI18n.t('localGenui.generatedApps'),
      generatedId: entry.appId,
      thumbnailPath: entry.thumbnailPath ?? ''
    }));
    return builtins.concat(generated);
  }

  private elementId(app: MiniAppGalleryItem, card: boolean): string {
    const id = app.id.replace(/[^A-Za-z0-9_-]/g, '_');
    return card ? `miniapp-card-${id}` : `miniapp-list-${id}`;
  }

  private select(app: MiniAppGalleryItem): void {
    this.state.galleryAppId = app.id;
    if (app.generatedId.length > 0) this.onOpenGenerated(app.generatedId);
    else this.onSelect(app.id);
  }

  private currentIndex(): number {
    return Math.max(0, this.items().findIndex((app: MiniAppGalleryItem): boolean => app.id === this.state.galleryAppId));
  }

  private focus(index: number): void {
    const app = this.items()[index];
    if (!app) return;
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => { this.state.galleryAppId = app.id; });
  }

  private preview(id: string): Resource {
    if (id === 'builtin-gomoku') return $r('app.media.miniapp_gomoku_preview');
    if (id === 'builtin-regex-playground') return $r('app.media.miniapp_regex_preview');
    return $r('app.media.miniapp_divination_preview');
  }
}
