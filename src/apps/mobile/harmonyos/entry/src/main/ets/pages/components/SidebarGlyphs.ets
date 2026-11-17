import { SIDEBAR_INK, SIDEBAR_MUTED, SIDEBAR_RAISED, STATUS_SUCCESS } from './Theme';
import { TemplateIcon } from './TemplateIcon';

@ComponentV2
export struct SidebarGlyph {
  @Param kind: string = '';
  @Param connectionState: string = '';
  @Param tint: ResourceColor = SIDEBAR_INK;
  @Param iconSize: number = 24;

  build() {
    if (this.kind === 'session_more') {
      this.MoreDots()
    } else if (this.kind === 'remote') {
      this.Remote()
    } else if (this.kind === 'search') {
      this.Search()
    } else if (this.kind === 'notebook') {
      this.Notebook()
    } else if (this.kind === 'clock') {
      this.Clock()
    } else if (this.kind === 'apps') {
      this.Apps()
    } else if (this.kind === 'assistant') {
      this.Assistant()
    } else if (this.kind === 'code_flower') {
      this.CodeFlower()
    } else if (this.kind === 'more') {
      this.More()
    } else if (this.kind === 'edit') {
      this.Edit()
    } else if (this.kind === 'settings') {
      this.Settings()
    }
  }

  @Builder
  private MoreDots() {
    Row({ space: 3 }) {
      Text('').width(3).height(3).backgroundColor(this.tint).borderRadius(2)
      Text('').width(3).height(3).backgroundColor(this.tint).borderRadius(2)
      Text('').width(3).height(3).backgroundColor(this.tint).borderRadius(2)
    }
    .width(15)
    .height(24)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private Remote() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.connectionState === 'connected' || this.connectionState === 'reconnecting') {
        TemplateIcon({ src: $r('app.media.remote_ref_sidebar_connected'), iconWidth: 35, iconHeight: 34 })
        Text('').width(8).height(8).backgroundColor(STATUS_SUCCESS).borderRadius(4)
          .position({ x: 24, y: 22 })
      } else {
        TemplateIcon({ src: $r('app.media.remote_logo'), iconWidth: 34, iconHeight: 34, tint: SIDEBAR_MUTED })
      }
    }
    .width(35).height(34)
  }

  @Builder
  private Search() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(Math.min(22, this.iconSize)).fontColor([this.tint])
    }
    .width(24)
    .height(24)
  }

  @Builder
  private Notebook() {
    Stack() {
      Text('').width(17).height(20).borderRadius(4).border({ width: 1.5, color: this.tint })
        .position({ x: 6, y: 2 })
      Text('').width(3).height(3).borderRadius(2).backgroundColor(this.tint)
        .position({ x: 2, y: 7 })
      Text('').width(3).height(3).borderRadius(2).backgroundColor(this.tint)
        .position({ x: 2, y: 15 })
    }
    .width(24).height(24)
  }

  @Builder
  private Clock() {
    Stack() {
      Text('').width(22).height(22).borderRadius(11).border({ width: 1.5, color: this.tint })
        .position({ x: 1, y: 1 })
      Text('').width(1.5).height(7).backgroundColor(this.tint).borderRadius(2)
        .position({ x: 11, y: 5 })
      Text('').width(7).height(1.5).backgroundColor(this.tint).borderRadius(2)
        .position({ x: 11, y: 11 })
    }
    .width(24).height(24)
  }

  @Builder
  private Apps() {
    Stack({ alignContent: Alignment.Center }) {
      TemplateIcon({ src: $r('app.media.sidebar_miniapps'), iconWidth: this.iconSize,
        iconHeight: this.iconSize, tint: this.tint })
    }
    .width(24).height(24)
  }

  @Builder
  private Assistant() {
    Stack({ alignContent: Alignment.Center }) {
      // The compact native assistant mark used by the mobile design system.
      Image($r('app.media.assistant_mascot'))
        .width(18)
        .height(18)
        .objectFit(ImageFit.Contain)
        .draggable(false)
    }
    .width(18)
    .height(18)
  }

  @Builder
  private CodeFlower() {
    Stack() {
      Text('').width(11).height(11).borderRadius(5.5).border({ width: 1.5, color: this.tint })
        .backgroundColor(SIDEBAR_RAISED).position({ x: 6, y: 0 })
      Text('').width(11).height(11).borderRadius(5.5).border({ width: 1.5, color: this.tint })
        .backgroundColor(SIDEBAR_RAISED).position({ x: 13, y: 6 })
      Text('').width(11).height(11).borderRadius(5.5).border({ width: 1.5, color: this.tint })
        .backgroundColor(SIDEBAR_RAISED).position({ x: 6, y: 13 })
      Text('').width(11).height(11).borderRadius(5.5).border({ width: 1.5, color: this.tint })
        .backgroundColor(SIDEBAR_RAISED).position({ x: 0, y: 6 })
      Text('').width(8).height(8).borderRadius(4).backgroundColor(SIDEBAR_RAISED)
        .position({ x: 8, y: 8 })
    }
    .width(24).height(24)
  }

  @Builder
  private More() {
    Row({ space: 5 }) { this.Dot(); this.Dot(); this.Dot(); }
      .width(24).height(24)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
  }

  @Builder
  private Dot() {
    Text('').width(5).height(5).borderRadius(3).backgroundColor(this.tint)
  }

  @Builder
  private Edit() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.square_and_pencil'))
        .fontSize(20)
        .fontColor([this.tint])
    }
    .width(24)
    .height(22)
  }

  @Builder
  private Settings() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.gearshape'))
        .fontSize(24)
        .fontColor([this.tint])
    }
    .width(24)
    .height(26)
  }
}
