import { INK } from './Theme';

/**
 * A system glyph keeps its native geometry inside a 24 vp drawing slot.
 * Interactive callers own the larger touch target around this component.
 */
@ComponentV2
export struct HarmonyIcon {
  @Require @Param symbol: Resource;
  @Param iconSize: number = 24;
  @Param tint: ResourceColor = INK;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(this.symbol)
        .fontSize(this.iconSize)
        .fontColor([this.tint])
    }
    .width(24)
    .height(24);
  }
}
