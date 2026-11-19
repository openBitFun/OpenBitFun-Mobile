import { MotionPreference } from '../../services/MotionPreference';
import { MiniAppShortcut } from '../../services/MiniAppShortcut';
import { RemoteLogger } from '../../services/RemoteLogger';
import { BusinessError } from '@kit.BasicServicesKit';
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
  @Event onOpenGenerated: (id: string) => void = (_id: string) => {};
  @Event onRemoveGenerated: (id: string) => void = (_id: string) => {};
  @Local failedThumbnails: string[] = [];
  @Local viewportWidth: number = 360;
  @Local stackHeight: number = 480;

  @Local lifted: MiniAppGalleryItem | null = null;
  private hintTimer: number = -1;
  private originX: number = 0;
  private originY: number = 0;

  @Local pinning: boolean = false;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.GalleryContent()

    }.width('100%').height('100%').clip(true)
      .onAreaChange((_old: Area, area: Area) => {
        this.originX = Number(area.globalPosition.x);
        this.originY = Number(area.globalPosition.y);

        this.viewportWidth = Number(area.width);
      })
  }

  @Builder
  private GalleryContent() {
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
            if (!this.lifted) this.focus(index);
          }))
        Row({ space: 8 }) {
          ForEach(this.items(), (app: MiniAppGalleryItem, index: number) => {
            Row().width(index === this.currentIndex() ? 24 : 8).height(8)
              .borderRadius(4).backgroundColor(index === this.currentIndex() ? INK : SUBTLE)
              .opacity(index === this.currentIndex() ? 1 : 0.4)
          }, (app: MiniAppGalleryItem): string => app.id)
        }.justifyContent(FlexAlign.Center).padding({ top: 20, bottom: this.bottomInset + 16 })
          .opacity(this.state.drag.active ? 0 : 1).accessibilityLevel('no')
      }
    }.width('100%').height('100%')

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
    .scale({ x: index === this.deckIndex() ? 1 : 0.85, y: index === this.deckIndex() ? 1 : 0.85 })
    .rotate({ angle: index === this.deckIndex() ? 0 : index < this.deckIndex() ? -5 : 5 })
    .translate({ x: (index - this.deckIndex()) * (this.viewportWidth >= 600 ? 60 : 70) })
    .opacity(this.lifted?.id === app.id ? 0 : index === this.deckIndex() ? 1 : Math.abs(index - this.deckIndex()) === 1 ? 0.6 : 0)
    .zIndex(index === this.deckIndex() ? 3 : 1)
    .hitTestBehavior(index === this.currentIndex() ? HitTestMode.Default : HitTestMode.None)
    .accessibilityLevel(index === this.currentIndex() ? 'yes' : 'no-hide-descendants')
    .accessibilityText(`${app.name}, ${app.description}`)
    .onClick(() => { if (index === this.currentIndex()) this.select(app); })
    .gesture(GestureGroup(GestureMode.Sequence,
      LongPressGesture({ duration: 380, repeat: false })
        .onAction((event: GestureEvent) => {
          if (this.pinning || index !== this.currentIndex()) return;
          this.beginLift(app, event);
        }),
      PanGesture({ direction: PanDirection.All, distance: 2 })
        .onActionUpdate((event: GestureEvent) => this.track(event))
        .onActionEnd((event: GestureEvent) => {
          this.track(event);
          this.drop();
        })
    ).onCancel(() => this.endLift()))
  }

  private track(event: GestureEvent): void {
    const finger = event.fingerList[0];
    if (finger) {
      this.state.drag.move(finger.globalX, finger.globalY);
    }
  }

  private beginLift(app: MiniAppGalleryItem, event: GestureEvent): void {
    const drag = this.state.drag;
    drag.setTargetTop(undefined);
    drag.bottomInset = this.bottomInset;
    drag.reduceMotion = MotionPreference.reduceMotion();
    this.track(event);
    drag.name = app.name;
    drag.description = app.description;
    drag.image = app.thumbnailPath && !this.failedThumbnails.includes(app.thumbnailPath) ?
      'file://' + app.thumbnailPath : this.iconResource(app);
    drag.width = MiniAppGalleryPolicy.cardWidth(this.viewportWidth);
    drag.initialWidth = drag.width;
    drag.height = MiniAppGalleryPolicy.cardHeight(this.viewportWidth, this.stackHeight);
    drag.coverHeight = drag.height * 0.65;
    drag.offsetX = this.originX + (this.viewportWidth - drag.width) / 2 - drag.fingerX;
    drag.offsetY = this.originY + (this.stackHeight - drag.height) / 2 - drag.fingerY;
    drag.contracted = false;
    drag.hintVisible = drag.reduceMotion;
    drag.active = true;
    this.lifted = app;
    this.getUIContext().animateToImmediately({ duration: drag.reduceMotion ? 0 : 300, curve: Curve.EaseOut }, () => {
      drag.width = 56;
      drag.height = 56;
      drag.coverHeight = 56;
      drag.offsetX = -28;
      drag.offsetY = -28;
      drag.contracted = true;
    });
    if (drag.reduceMotion) return;
    this.hintTimer = setTimeout(() => {
      this.getUIContext().animateTo({ duration: 150, curve: Curve.EaseOut }, () => { drag.hintVisible = true; });
    }, 200);
  }

  private endLift(): void {
    clearTimeout(this.hintTimer);
    this.lifted = null;
    this.state.drag.active = false;
  }

  aboutToDisappear(): void {
    this.endLift();
  }

  private drop(): void {
    const app = this.lifted;
    const accepted = this.state.drag.overEdge;
    this.endLift();
    if (app && accepted) void this.pin(app, true);
  }

  private deckIndex(): number {
    const current = this.currentIndex();
    if (!this.state.drag.contracted || !this.state.drag.active || this.items().length < 2) return current;
    return current + 1 < this.items().length ? current + 1 : current - 1;
  }

  private iconResource(app: MiniAppGalleryItem): Resource {
    return app.generatedId ? $r('app.media.openbitfun_app_icon') : this.preview(app.id);
  }

  private async pin(app: MiniAppGalleryItem, revealDesktop: boolean = false): Promise<void> {
    if (this.pinning) return;
    this.pinning = true;
    let code: number = -1;
    try {
      code = await MiniAppShortcut.pin(this.getUIContext().getHostContext()!,
        app.generatedId || app.id, app.name, !!app.generatedId,
        this.failedThumbnails.includes(app.thumbnailPath) ? '' : app.thumbnailPath, this.iconResource(app), revealDesktop);
    } catch (error) {
      code = (error as BusinessError).code || -1;
      RemoteLogger.warn('Mini app shortcut request failed: ' + code);
    } finally {
      this.pinning = false;
    }
    if (code === 1006620007 || (code === 0 && revealDesktop)) return;
    const key = code === 0 ? 'miniapp.pinned' : code === 1006620003 ? 'miniapp.alreadyPinned' :
      code === 1006620004 ? 'miniapp.pinLimit' : 'miniapp.pinFailed';
    this.getUIContext().getPromptAction().showToast({ message: code !== 0 && key === 'miniapp.pinFailed' ?
      RemoteI18n.f(key, String(code)) : RemoteI18n.t(key) });
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
            .bindContextMenu(this.GeneratedActions(app), ResponseType.LongPress)
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
  private GeneratedActions(app: MiniAppGalleryItem) {
    Menu() {
      MenuItem({ content: RemoteI18n.t('miniapp.pinIcon') }).onClick(() => { void this.pin(app); })
      if (app.generatedId.length > 0) {
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
