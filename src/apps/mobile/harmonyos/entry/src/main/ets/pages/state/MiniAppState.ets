import { MiniAppDragState } from './MiniAppDragState';
import { MiniAppSummary } from '../../model/MiniAppModels';

@ObservedV2
export class MiniAppState {
  readonly drag: MiniAppDragState = new MiniAppDragState();
  @Trace galleryMode: string = 'cards';
  @Trace galleryAppId: string = '';
  @Trace visible: boolean = false;
  @Trace loading: boolean = false;
  @Trace error: string = '';
  @Trace apps: MiniAppSummary[] = [];
  @Trace appId: string = '';
  @Trace name: string = '';
  @Trace document: string = '';
  @Trace revision: number = 0;
}
