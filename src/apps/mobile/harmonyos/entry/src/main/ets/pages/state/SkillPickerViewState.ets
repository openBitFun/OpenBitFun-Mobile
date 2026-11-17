import { COMMAND_CATALOG_FILTER_ALL } from '../../services/CommandCatalogProjection';

/** Search and filter within one open picker, retained across fold remounts. */
@ObservedV2
export class SkillPickerViewState {
  @Trace query: string = '';
  @Trace filterId: string = COMMAND_CATALOG_FILTER_ALL;

  reset(): void {
    this.query = '';
    this.filterId = COMMAND_CATALOG_FILTER_ALL;
  }
}
