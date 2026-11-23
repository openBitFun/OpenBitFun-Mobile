import { MobileDesignGeometry, MobileDesignTypography } from '../../generated/MobileDesignTokens';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { LocalGenUIModelProfile } from '../../services/local-genui/LocalGenUIModelCatalog';
import { LocalGenUIActions, LocalGenUIState, emptyLocalGenUIActions } from '../state/LocalGenUIState';
import { CARD, CONTENT_ON_ACTION, INK, LINE, MUTED, PAGE_BG, PRIMARY_ACTION, SHADOW_FAINT, SOFT, STATUS_DANGER, SUBTLE } from './Theme';
import { SheetCloseHeader } from './SheetCloseHeader';
import { AppActionButton, AppActionStyle } from './AppActionButton';

/** Same field treatment as the model-service settings panel. */
class LocalFieldStyle implements AttributeModifier<TextInputAttribute> {
  applyNormalAttribute(instance: TextInputAttribute): void {
    instance.width('100%')
      .height(MobileDesignGeometry.genuiModelFieldHeight)
      .fontSize(MobileDesignTypography.titleSmall.size)
      .fontColor(INK)
      .placeholderColor(SUBTLE)
      .backgroundColor(CARD)
      .border({ width: 0.5, color: LINE })
      .borderRadius(MobileDesignGeometry.settingsCompactCardRadius)
      .shadow({ radius: 12, color: SHADOW_FAINT, offsetY: 4 })
      .padding({ left: MobileDesignGeometry.genuiModelFieldPadding, right: MobileDesignGeometry.genuiModelFieldPadding });
  }
}

/**
 * Model profiles of Local GenUI Mode: list, add, edit and delete. Keys are
 * entered here and stored encrypted on the phone; they are never displayed.
 */
@ComponentV2
export struct LocalGenUIModelManager {
  @Param state: LocalGenUIState = new LocalGenUIState();
  @Param actions: LocalGenUIActions = emptyLocalGenUIActions();
  @Local name: string = '';
  @Local apiUrl: string = '';
  @Local modelName: string = '';
  @Local apiKey: string = '';

  aboutToAppear(): void {
    this.onEditorChange();
  }

  @Monitor('state.editorOpen', 'state.editingModelId')
  onEditorChange(): void {
    if (!this.state.editorOpen) return;
    const model = this.state.models.find((item: LocalGenUIModelProfile) => item.id === this.state.editingModelId);
    this.name = model ? model.name : '';
    this.apiUrl = model ? model.apiUrl : '';
    this.modelName = model ? model.modelName : '';
    this.apiKey = '';
  }

  build() {
    Column() {
      SheetCloseHeader({
        title: this.state.configuringModel ? RemoteI18n.t('localGenui.configureModel') : this.state.editorOpen
          ? RemoteI18n.t(this.state.editingModelId === 'new' ? 'localGenui.addModel' : 'localGenui.editModel')
          : RemoteI18n.t('localGenui.manageModels'),
        showDivider: true,
        isEnabled: !this.state.editorSaving,
        onClose: (): void => {
          if (this.state.editorOpen) this.actions.closeEditor();
          else this.actions.closeModelManager();
        }
      })

      if (this.state.editorOpen) {
        this.Editor()
      } else {
        this.ModelList()
      }
    }
    .width('100%').height('100%').backgroundColor(PAGE_BG)
  }

  @Builder
  ModelList() {
    Scroll() {
      Column({ space: MobileDesignGeometry.genuiModelListSpacing }) {
        if (this.state.models.length === 0) {
          Text(RemoteI18n.t('localGenui.noModels'))
            .fontSize(MobileDesignTypography.bodyMedium.size).fontColor(MUTED).padding({ top: 8, bottom: 8 })
        }
        ForEach(this.state.models, (model: LocalGenUIModelProfile) => {
          Row({ space: 10 }) {
            Column({ space: 2 }) {
              Text(model.name.trim().length > 0 ? model.name : model.modelName)
                .fontSize(MobileDesignTypography.bodyMedium.size).fontWeight(FontWeight.Medium).fontColor(INK)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${model.modelName} · ${this.host(model.apiUrl)}`)
                .fontSize(MobileDesignTypography.labelSmall.size).fontColor(MUTED)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            if (model.id === this.state.currentModelId) {
              Text(RemoteI18n.t('settings.modelService.currentModel')).fontSize(MobileDesignTypography.labelSmall.size).fontColor(MUTED)
            }
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([MUTED])
          }
          .width('100%').padding(MobileDesignGeometry.genuiModelFieldPadding).borderRadius(MobileDesignGeometry.settingsCardRadius).backgroundColor(CARD).border({ width: 1, color: LINE })
          .enabled(!this.state.editorSaving)
          .onClick(() => {
            if (this.state.configuringModel) this.actions.useModel(model.id);
            else this.actions.editModel(model.id);
          })
        }, (model: LocalGenUIModelProfile) => `${model.id}:${model.name}:${model.modelName}:${model.apiUrl}`)
        AppActionButton({
          label: RemoteI18n.t('localGenui.addModel'),
          style: AppActionStyle.Primary,
          actionHeight: MobileDesignGeometry.genuiModelActionHeight,
          isEnabled: !this.state.editorSaving,
          onAction: (): void => this.actions.editModel('new')
        })
        if (this.state.editorError.length > 0) {
          Text(this.state.editorError).fontSize(MobileDesignTypography.bodySmall.size).fontColor(STATUS_DANGER)
        }
      }
      .width('100%').padding({ left: 16, right: 16, bottom: 24 })
    }
    .width('100%').layoutWeight(1).align(Alignment.Top)
  }

  @Builder
  Editor() {
    Scroll() {
      Column({ space: MobileDesignGeometry.genuiModelEditorSpacing }) {
        this.Field(RemoteI18n.t('localGenui.modelDisplayName'))
        TextInput({ text: this.name, placeholder: RemoteI18n.t('localGenui.modelDisplayNameHint') })
          .attributeModifier(new LocalFieldStyle())
          .onChange((value: string) => { this.name = value; })
        this.Field(RemoteI18n.t('settings.modelService.apiUrl'))
        TextInput({ text: this.apiUrl, placeholder: 'https://api.example.com/v1' })
          .id('local-genui-model-url')
          .attributeModifier(new LocalFieldStyle())
          .type(InputType.URL)
          .onChange((value: string) => { this.apiUrl = value; })
        this.Field(RemoteI18n.t('localGenui.apiKey'))
        TextInput({ text: this.apiKey, placeholder: this.state.editorHasKey ? RemoteI18n.t('localGenui.apiKeyKept') : RemoteI18n.t('localGenui.apiKey') })
          .id('local-genui-model-key')
          .attributeModifier(new LocalFieldStyle())
          .type(InputType.Password)
          .showPasswordIcon(true)
          .onChange((value: string) => { this.apiKey = value; })
        Row({ space: 8 }) {
          this.Field(RemoteI18n.t('settings.modelService.modelName'))
          Blank()
          if (this.state.fetchingModels) {
            LoadingProgress().width(18).height(18)
          }
          Text(RemoteI18n.t('localGenui.fetchModels'))
            .fontSize(MobileDesignTypography.labelSmall.size).fontColor(INK)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 }).borderRadius(MobileDesignGeometry.genuiModelChipRadius).backgroundColor(SOFT)
            .enabled(!this.state.fetchingModels && this.apiUrl.trim().length > 0)
            .onClick(() => this.actions.fetchRemoteModels(this.apiUrl, this.apiKey))
        }.width('100%')
        TextInput({ text: this.modelName, placeholder: RemoteI18n.t('settings.modelService.modelName') })
          .id('local-genui-model-name')
          .attributeModifier(new LocalFieldStyle())
          .onChange((value: string) => { this.modelName = value; })
        if (this.state.remoteModelNames.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.state.remoteModelNames, (name: string) => {
              Text(name)
                .fontSize(MobileDesignTypography.labelSmall.size)
                .fontColor(name === this.modelName ? CONTENT_ON_ACTION : INK)
                .backgroundColor(name === this.modelName ? PRIMARY_ACTION : SOFT)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 }).borderRadius(MobileDesignGeometry.genuiModelChipRadius)
                .margin({ right: 8, bottom: 8 })
                .onClick(() => { this.modelName = name; })
            }, (name: string) => name)
          }.width('100%')
        }
        if (this.state.editorError.length > 0) {
          Text(this.state.editorError).fontSize(MobileDesignTypography.bodySmall.size).fontColor(STATUS_DANGER)
            .copyOption(CopyOptions.InApp)
        }
        AppActionButton({
          label: RemoteI18n.t(this.state.editorSaving ? 'common.loading' :
            (this.state.configuringModel ? 'localGenui.saveAndUseModel' : 'common.save')),
          style: AppActionStyle.Primary,
          actionHeight: MobileDesignGeometry.genuiModelActionHeight,
          isEnabled: !this.state.editorSaving,
          onAction: (): void => this.actions.saveModel({ name: this.name, apiUrl: this.apiUrl, modelName: this.modelName, apiKey: this.apiKey })
        })
        if (!this.state.configuringModel && this.state.editingModelId !== 'new') {
          AppActionButton({
            label: RemoteI18n.t('localGenui.deleteModel'),
            style: AppActionStyle.Destructive,
            actionHeight: MobileDesignGeometry.genuiModelActionHeight,
            onAction: (): void => this.actions.removeModel(this.state.editingModelId)
          })
        }
      }
      .width('100%').padding({ left: 16, right: 16, bottom: 24 }).alignItems(HorizontalAlign.Start)
    }
    .width('100%').layoutWeight(1).align(Alignment.Top)
  }

  @Builder
  Field(label: string) {
    Text(label).fontSize(MobileDesignTypography.bodyMedium.size).fontWeight(FontWeight.Medium).fontColor(INK)
  }

  private host(url: string): string {
    const withoutScheme = url.replace(/^https?:\/\//, '');
    const slash = withoutScheme.indexOf('/');
    return slash >= 0 ? withoutScheme.slice(0, slash) : withoutScheme;
  }
}
