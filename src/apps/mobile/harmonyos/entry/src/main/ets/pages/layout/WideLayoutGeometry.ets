import { FilePreviewLayout, FilePreviewPlacement } from '../policy/FilePreviewPlacementPolicy';
import { ConversationLayoutPolicy } from '../policy/ConversationLayoutPolicy';

/** Pure geometry helpers shared by wide conversation presentation paths. */
export class WideLayoutGeometry {
  static readonly MASTER_PANE_VERTICAL_PADDING: number = 10;
  /** The design-lab sidebar occupies roughly 60% of a physical master pane. */
  static readonly MASTER_PANE_SURFACE_RATIO: number = 0.60;

  static masterPaneWidth(layout: FilePreviewLayout, fallback: number): number {
    return layout.placement === FilePreviewPlacement.WideTriplePane ||
      layout.placement === FilePreviewPlacement.WideMasterPreviewFocus ? layout.masterPaneWidth : fallback;
  }

  /** Keep the visible navigation card at the design-lab mobile proportion. */
  static masterPaneSurfaceWidth(masterPaneWidth: number): number {
    if (masterPaneWidth <= 0) {
      return ConversationLayoutPolicy.FALLBACK_MASTER_PANE_WIDTH;
    }
    return Math.max(220, Math.round(masterPaneWidth * WideLayoutGeometry.MASTER_PANE_SURFACE_RATIO));
  }

  /**
   * Width consumed by the master pane in the parent Row. Keep this separate
   * from the physical pane width so the detail pane receives the space freed
   * by the compact sidebar on foldable screens.
   */
  static masterPaneLayoutWidth(layout: FilePreviewLayout, fallback: number): number {
    return WideLayoutGeometry.masterPaneSurfaceWidth(
      WideLayoutGeometry.masterPaneWidth(layout, fallback)
    );
  }

  static masterPaneFreedWidth(layout: FilePreviewLayout, fallback: number): number {
    const physicalWidth = WideLayoutGeometry.masterPaneWidth(layout, fallback);
    return Math.max(0, physicalWidth - WideLayoutGeometry.masterPaneSurfaceWidth(physicalWidth));
  }

  static detailOffset(collapsed: boolean, expandedOffset: number, collapsedOffset: number): number {
    return collapsed ? collapsedOffset : expandedOffset;
  }

  static detailWidth(collapsed: boolean, expandedWidth: number, collapsedWidth: number): number {
    return collapsed ? collapsedWidth : expandedWidth;
  }

  static showsMasterRestoreButton(collapsed: boolean, layout: FilePreviewLayout): boolean {
    return collapsed || layout.placement === FilePreviewPlacement.WideFocusSplit;
  }

  static restoreMasterClosesPreview(layout: FilePreviewLayout): boolean {
    return layout.placement === FilePreviewPlacement.WideFocusSplit;
  }

  static areaLength(value: Object): number {
    const parsed = Number.parseFloat(`${value}`);
    return Number.isNaN(parsed) ? 0 : parsed;
  }
}
