import { MobileDesignGeometry } from '../../generated/MobileDesignTokens';

/**
 * Mobile sidebar rhythm shared by compact and wide presentations.
 *
 * These values mirror the mobile sidebar primitives from the design system:
 * header/section/entry rows stay intentionally compact, while session rows
 * keep the slightly more generous reading rhythm used by the design lab.
 * Touch targets remain owned by the controls inside the rows.
 */
export class SidebarLayoutPolicy {
  static readonly HEADER_HEIGHT: number = 40;
  static readonly ENTRY_ROW_HEIGHT: number = 36;
  static readonly SECTION_LABEL_HEIGHT: number = 28;
  static readonly DEVICE_SECTION_HEADER_HEIGHT: number = SidebarLayoutPolicy.SECTION_LABEL_HEIGHT;
  static readonly DEVICE_ROW_HEIGHT: number = SidebarLayoutPolicy.ENTRY_ROW_HEIGHT;
  static readonly WORKSPACE_SECTION_HEADER_HEIGHT: number = SidebarLayoutPolicy.SECTION_LABEL_HEIGHT;
  static readonly WORKSPACE_ROW_HEIGHT: number = SidebarLayoutPolicy.ENTRY_ROW_HEIGHT;
  static readonly CHILD_ROW_HEIGHT: number = SidebarLayoutPolicy.ENTRY_ROW_HEIGHT;
  static readonly SESSION_ROW_HEIGHT: number = 40;
  static readonly AUXILIARY_ROW_HEIGHT: number = 40;
  static readonly HEADER_HORIZONTAL_PADDING: number = 12;
  static readonly ROW_HORIZONTAL_PADDING: number = 8;
  // Header controls occupy the full trailing slot; inset rows consume its
  // middle so every glyph and status indicator shares the same right axis.
  static readonly TRAILING_SLOT_SIZE: number = MobileDesignGeometry.sidebarTrailingSlotWidth;
  static readonly INSET_TRAILING_SLOT_SIZE: number = SidebarLayoutPolicy.TRAILING_SLOT_SIZE -
    SidebarLayoutPolicy.ROW_HORIZONTAL_PADDING * 2;
  static readonly ROW_GAP: number = 8;
  static readonly ICON_SLOT_SIZE: number = 16;
  static readonly PROMINENT_ICON_SLOT_SIZE: number = 18;
  static readonly STATUS_DOT_SIZE: number = 6;
  static readonly CHILD_INDENT: number = 28;
  static readonly FOOTER_HEIGHT: number = MobileDesignGeometry.sidebarFooterHeight;
  static readonly FOOTER_PADDING: number = 8;
  static readonly FOOTER_TOOL_HEIGHT: number = MobileDesignGeometry.sidebarFooterTouchSize;
  static readonly FOOTER_TOOL_MIN_WIDTH: number = 88;
  static readonly FOOTER_SETTINGS_SIZE: number = MobileDesignGeometry.sidebarFooterTouchSize;
}
