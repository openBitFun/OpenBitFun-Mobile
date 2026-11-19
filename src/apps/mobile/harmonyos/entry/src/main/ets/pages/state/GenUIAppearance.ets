import { PersistenceV2 } from '@kit.ArkUI';

export const GENUI_LOOKS: string[] = ['classic', 'aurora', 'blueprint', 'celadon'];

@ObservedV2
export class GenUIAppearance {
  @Trace look: string = 'aurora';

  static connect(): GenUIAppearance {
    return PersistenceV2.globalConnect<GenUIAppearance>({
      type: GenUIAppearance,
      key: 'localGenUIAppearance',
      defaultCreator: (): GenUIAppearance => new GenUIAppearance()
    })!;
  }

  current(): string {
    return GENUI_LOOKS.includes(this.look) ? this.look : 'aurora';
  }
}
