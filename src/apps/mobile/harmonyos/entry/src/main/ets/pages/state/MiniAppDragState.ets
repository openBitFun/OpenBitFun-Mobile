/** Geometry is in window vp, so a drag can leave the gallery pane on a foldable. */
@ObservedV2
export class MiniAppDragState {
  static readonly GLOW_HEIGHT: number = 72;
  reduceMotion: boolean = false;
  @Trace active: boolean = false;
  @Trace contracted: boolean = false;
  @Trace hintVisible: boolean = false;
  @Trace overEdge: boolean = false;
  @Trace image: ResourceStr = '';
  @Trace name: string = '';
  @Trace description: string = '';
  @Trace fingerX: number = 0;
  @Trace fingerY: number = 0;
  @Trace offsetX: number = 0;
  @Trace offsetY: number = 0;
  @Trace width: number = 0;
  @Trace height: number = 0;
  @Trace coverHeight: number = 0;
  initialWidth: number = 0;
  bottomInset: number = 0;
  windowX: number = 0;
  windowY: number = 0;
  windowWidth: number = 0;
  windowHeight: number = 0;

  private targetTop: number | undefined = undefined;

  setTargetTop(top: number | undefined): void {
    this.targetTop = top;
    this.updateOverEdge();
  }

  move(x: number, y: number): void {
    this.fingerX = x;
    this.fingerY = y;
    this.updateOverEdge();
  }

  private updateOverEdge(): void {
    this.overEdge = this.targetTop !== undefined &&
      this.fingerX >= this.windowX && this.fingerX <= this.windowX + this.windowWidth &&
      this.fingerY >= this.targetTop && this.fingerY <= this.windowY + this.windowHeight;
  }
}
