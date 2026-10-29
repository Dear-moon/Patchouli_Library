import common from '@ohos.app.ability.common';
import deviceInfo from '@ohos.deviceInfo';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import util from '@ohos.util';
import { BusinessError } from '@ohos.base';

export class GallerySaveFailure extends Error {
  readonly code: string;
  constructor(code: string, message: string) { super(message); this.code = code; }
}

interface GallerySaveGrant { viewId: number; expiresAt: number; }

/** App-side action ownership; the actual privilege is granted only by SaveButton. */
export class GallerySaveAuthorizations {
  private grants: Map<string, GallerySaveGrant> = new Map();

  authorized(viewId: number): string {
    this.revoke(viewId);
    const now = Date.now();
    this.grants.forEach((grant: GallerySaveGrant, token: string): void => {
      if (grant.expiresAt <= now) { this.grants.delete(token); }
    });
    const token = util.generateRandomUUID(true);
    this.grants.set(token, { viewId: viewId, expiresAt: now + (deviceInfo.sdkApiVersion >= 20 ? 60000 : 10000) });
    return token;
  }

  consume(token: string | null | undefined): void {
    const grant = typeof token === 'string' ? this.grants.get(token) : undefined;
    if (typeof token === 'string') { this.grants.delete(token); }
    if (!grant || grant.expiresAt <= Date.now()) {
      throw new GallerySaveFailure('gallery_permission', '保存授权已失效，请再次点击“保存图片”');
    }
  }

  revoke(viewId: number): void {
    this.grants.forEach((grant: GallerySaveGrant, token: string): void => {
      if (grant.viewId === viewId) { this.grants.delete(token); }
    });
  }

  clear(): void { this.grants.clear(); }
}

/** One complete original-byte submission; no file picker or gallery read grant. */
export async function saveGalleryImage(context: common.UIAbilityContext, bytes: Uint8Array,
  name: string, authorizations: GallerySaveAuthorizations, token: string | null | undefined): Promise<void> {
  const dot = name.lastIndexOf('.');
  const extension = name.substring(dot + 1);
  const title = name.substring(0, dot).replace(/[\\/:*?"'`<>|{}\[\]\x00-\x1f\x7f]/g, '_').replace(/\.\./g, '_').trim() || '文库图片';
  const helper = photoAccessHelper.getPhotoAccessHelper(context);
  try {
    const request = photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(
      context, photoAccessHelper.PhotoType.IMAGE, extension, { title: title });
    request.addResource(photoAccessHelper.ResourceType.IMAGE_RESOURCE,
      bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
    authorizations.consume(token);
    await helper.applyChanges(request);
  } catch (error) {
    if (error instanceof GallerySaveFailure) { throw error; }
    const code = (error as BusinessError).code;
    if (code === 201 || code === 13900012) {
      throw new GallerySaveFailure('gallery_permission', '未获得相册保存授权，请再次点击“保存图片”并允许保存');
    }
    throw new GallerySaveFailure('gallery_save_failed', '图片未能保存到相册，请检查可用空间后重试');
  } finally {
    // A completed media transaction must not become a failure if releasing its
    // client handle fails after the image is already committed.
    try { await helper.release(); } catch (_) {}
  }
}
