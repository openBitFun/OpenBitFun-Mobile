/**
 * 2x2 desktop card of one generated app. Service widgets bind data through
 * `@LocalStorageProp`, which only V1 `@Entry @Component` pages support, so
 * this page is V1 by platform requirement; it lives outside `pages/` and holds
 * no app logic. Keys mirror `LocalGenUIDesktopCardData`.
 */
const storage: LocalStorage = new LocalStorage();

@Entry(storage)
@Component
struct LocalGenUIAppCard {
  @LocalStorageProp('appId') appId: string = '';
  @LocalStorageProp('state') cardState: string = 'pending';
  @LocalStorageProp('title') title: string = '';
  @LocalStorageProp('initial') initial: string = 'AI';
  @LocalStorageProp('imageName') imageName: string = '';

  private open(): void {
    const params: Record<string, string> = {};
    if (this.appId.length > 0) {
      params['openbitfunLocalGenUIApp'] = this.appId;
    }
    postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: params });
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.cardState === 'ready' && this.imageName.length > 0) {
        Image(`memory://${this.imageName}`)
          .width('100%').height('100%').objectFit(ImageFit.Cover)
      } else {
        Column({ space: 4 }) {
          if (this.cardState === 'pending' && this.title.length === 0) {
            Image($r('app.media.openbitfun_app_icon')).width(40).height(40).borderRadius(10)
          } else {
            Text(this.initial)
              .fontSize(36).fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.connect_hero_accent'))
              .opacity(this.cardState === 'missing' ? 0.4 : 1)
          }
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
        .linearGradient({
          angle: 145,
          colors: [[$r('app.color.connect_hero_surface'), 0], [$r('app.color.connect_hero_bg'), 1]]
        })
      }
      Column({ space: 2 }) {
        Text(this.title.length > 0 ? this.title : $r('app.string.genui_card_name'))
          .fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_on_action'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.cardState === 'missing') {
          Text($r('app.string.genui_card_missing'))
            .fontSize(10).fontColor($r('app.color.content_on_action')).opacity(0.85)
            .maxLines(1)
        } else if (this.cardState === 'pending') {
          Text($r('app.string.genui_card_pending'))
            .fontSize(10).fontColor($r('app.color.content_on_action')).opacity(0.85)
            .maxLines(1)
        }
      }
      .width('100%').alignItems(HorizontalAlign.Start)
      .padding({ left: 10, right: 10, top: 6, bottom: 8 })
      .backgroundColor($r('app.color.toast_background'))
    }
    .width('100%').height('100%').clip(true)
    .backgroundColor($r('app.color.card'))
    .onClick(() => this.open())
  }
}
