import { RemoteI18n } from '../../i18n/RemoteI18n';
import { MotionPreference } from '../../services/MotionPreference';
import { INK } from './Theme';
import { MobileDesignGeometry as G } from '../../generated/MobileDesignTokens';

/** The original welcome phrase sequence, shared without repainting its host's session list. */
@ComponentV2
export struct WelcomePhrase {
  @Param fontSize: number = G.welcomeWordSize;
  @Param longWordFontSize: number = G.welcomeLongWordSize;
  @Param stageHeight: number = G.welcomeStageHeight;
  @Local elapsed: number = 0;
  private timer: number = -1;
  private started: number = 0;

  aboutToDisappear(): void { this.stop(); }

  private stop(): void { if (this.timer >= 0) clearInterval(this.timer); this.timer = -1; }
  private play(): void {
    this.stop();
    if (MotionPreference.reduceMotion()) { this.elapsed = 2700; return; }
    this.started = Date.now();
    this.timer = setInterval(() => { this.elapsed = Date.now() - this.started; }, 16);
  }
  private phrases(): string[] {
    return ['OpenBitFun', RemoteI18n.t('home.welcome_work'), RemoteI18n.t('home.welcome_play'), RemoteI18n.t('home.welcome_yours')];
  }
  private duration(word: string): number { return 250 + word.length * 185 + (word === 'OpenBitFun' ? 600 : 0) + 1800 + 650; }
  private phraseIndex(): number {
    const words = this.phrases();
    let total = 0;
    for (const word of words) total += this.duration(word);
    let time = this.elapsed % total;
    for (let i = 0; i < words.length; i++) { if (time < this.duration(words[i])) return i; time -= this.duration(words[i]); }
    return 0;
  }
  private word(): string { return this.phrases()[this.phraseIndex()]; }
  private time(): number {
    const words = this.phrases();
    let total = 0;
    for (const word of words) total += this.duration(word);
    let time = this.elapsed % total;
    for (let i = 0; i < this.phraseIndex(); i++) time -= this.duration(words[i]);
    return time;
  }
  private clamp(value: number): number { return Math.max(0, Math.min(1, value)); }
  private progress(index: number): number { return this.clamp((this.time() - 180 - index * 55) / 800); }
  private exitProgress(): number { return this.clamp((this.time() - this.duration(this.word()) + 650) / 650); }
  private bump(index: number): number { const p = this.progress(index); return Math.sin(p * Math.PI) * (1-p); }
  private glyphOffset(index: number): number {
    return Math.pow(1-this.progress(index), 3) * 38 - this.bump(index) * 5 - Math.pow(this.exitProgress(), 2) * 30;
  }

  build() {
    Row() {
      ForEach(this.word().split(''), (letter: string, index: number) => {
        Stack() { this.Glyph(letter, this.word().length > 12 ? this.longWordFontSize : this.fontSize); }
          .opacity(this.clamp(this.progress(index)*3)*(1-this.exitProgress()))
          .translate({ x: this.glyphOffset(index) })
          .scale({ x: 1+this.bump(index)*0.045, y: 1+this.bump(index)*0.045 })
      }, (letter: string, index: number) => `${this.phraseIndex()}-${index}-${letter}`)
    }.height(this.stageHeight).accessibilityGroup(true).accessibilityText(this.word())
    .onVisibleAreaChange([0], (visible: boolean) => { if (visible) this.play(); else this.stop(); })
  }

  @Builder
  private Glyph(letter: string, size: number) {
    if (letter === 'i') {
      Stack({ alignContent: Alignment.Top }) {
        Text('ı').fontSize(size).fontWeight(FontWeight.Medium).fontColor(INK)
        Circle().width(size*0.14).height(size*0.14).fill($r('app.color.brand_dot')).translate({ y: size*0.25 })
      }
    } else {
      Text(letter).fontSize(size).fontWeight(FontWeight.Medium).fontColor(INK)
    }
  }

}
