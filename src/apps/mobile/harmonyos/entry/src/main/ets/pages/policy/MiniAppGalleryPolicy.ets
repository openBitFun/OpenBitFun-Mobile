import { MobileDesignGeometry } from '../../generated/MobileDesignTokens';

/** Geometry follows the live content viewport, including an unfolded drawer. */
export class MiniAppGalleryPolicy {
  static columns(width: number): number { return width >= 840 ? 2 : 1; }
  static cardWidth(width: number): number {
    const maximum = width >= 840 ? MobileDesignGeometry.miniappWideCardWidth :
      width >= 600 ? MobileDesignGeometry.miniappFoldCardWidth : MobileDesignGeometry.miniappCardWidth;
    return Math.min(maximum, width * 0.82);
  }
  static cardHeight(width: number, height: number): number {
    const maximum = width >= 840 ? MobileDesignGeometry.miniappWideCardHeight :
      width >= 600 ? MobileDesignGeometry.miniappFoldCardHeight : MobileDesignGeometry.miniappCardHeight;
    return Math.max(0, Math.min(maximum, height - 40));
  }
  static nextIndex(index: number, offset: number, count: number): number {
    if (count === 0) return 0;
    const direction = offset < -48 ? 1 : offset > 48 ? -1 : 0;
    return Math.max(0, Math.min(count - 1, index + direction));
  }
}
