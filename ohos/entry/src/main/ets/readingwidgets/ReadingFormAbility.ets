import FormExtensionAbility from '@ohos.app.form.FormExtensionAbility';
import formBindingData from '@ohos.app.form.formBindingData';
import formInfo from '@ohos.app.form.formInfo';
import Want from '@ohos.app.ability.Want';
import { Configuration } from '@ohos.app.ability.Configuration';
import fs from '@ohos.file.fs';
import hilog from '@ohos.hilog';
import ReadingWidgetStore from './ReadingWidgetStore';

export default class ReadingFormAbility extends FormExtensionAbility {
  private initialImages: fs.File[] = [];

  onAddForm(want: Want): formBindingData.FormBindingData {
    const store = this.store();
    const id = String(want.parameters?.[formInfo.FormParam.IDENTITY_KEY] ?? '');
    const dimension = Number(want.parameters?.[formInfo.FormParam.DIMENSION_KEY] ?? 2);
    const name = String(want.parameters?.[formInfo.FormParam.NAME_KEY] ?? 'ReadingArchiveWidget');
    const cardId = name === 'ReadingArchiveWidget' ? 'focus' : name.replace('ReadingCard_', '');
    store.register(id, dimension, Number(want.parameters?.[formInfo.FormParam.WIDTH_KEY]),
      Number(want.parameters?.[formInfo.FormParam.HEIGHT_KEY]), cardId);
    const transfer = store.transfer(dimension, store.read(), store.boundsFor(id), id);
    // onAddForm returns synchronously. Keep the image alive until the provider's
    // documented onStop lifecycle; no timer or permanent service is required.
    if (transfer.file !== null) { this.initialImages.push(transfer.file); }
    this.initialImages.push(...(transfer.extraFiles ?? []));
    return transfer.binding;
  }

  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    if (wantParams !== undefined && (wantParams[formInfo.FormParam.WIDTH_KEY] !== undefined ||
      wantParams[formInfo.FormParam.HEIGHT_KEY] !== undefined)) {
      const store = this.store();
      store.register(formId, store.dimensionFor(formId), Number(wantParams[formInfo.FormParam.WIDTH_KEY]),
        Number(wantParams[formInfo.FormParam.HEIGHT_KEY]));
    }
    this.refresh(formId);
  }
  onRemoveForm(formId: string): void { this.store().remove(formId); }
  onFormEvent(formId: string, message: string): void {
    try { const event = JSON.parse(message) as Record<string, string>;
      if (event['action'] === 'nextQuote') { this.store().nextQuote(formId).catch((_error: Error): void => {}); }
    } catch (_) {}
  }
  onConfigurationUpdate(configuration: Configuration): void {
    this.store().updateAll().catch((_error: Error): void => {});
  }
  onSizeChanged(formId: string, newDimension: formInfo.FormDimension, newRect?: formInfo.Rect): void {
    this.store().register(formId, newDimension, newRect?.width, newRect?.height);
    this.refresh(formId);
  }
  onAcquireFormState(want: Want): formInfo.FormState { return formInfo.FormState.READY; }
  onStop(): void {
    for (const file of this.initialImages) { try { fs.closeSync(file); } catch (_) {} }
    this.initialImages = [];
  }

  private store(): ReadingWidgetStore { return new ReadingWidgetStore(this.context.getApplicationContext()); }
  private refresh(id: string): void {
    this.store().update(id).catch((error: Error): void => {
      hilog.warn(0, 'ReadingWidgets', '卡片更新待重试：%{public}s', error.name);
    });
  }
}
