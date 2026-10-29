import { PlatformView, PlatformViewFactory, StandardMessageCodec, BinaryMessenger, MethodChannel, MethodCall, MethodResult, Any } from '@ohos/flutter_ohos';
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import common from '@ohos.app.ability.common';
import { GallerySaveAuthorizations } from './HarmonyGalleryAccess';

interface GalleryButtonStyle { enabled: boolean; foreground: number; background: number; }

/** The visible button itself is the OS security component, never a click proxy. */
export default class HarmonyGallerySaveButtonFactory extends PlatformViewFactory {
  private messenger: BinaryMessenger;
  private authorizations: GallerySaveAuthorizations;
  constructor(messenger: BinaryMessenger, authorizations: GallerySaveAuthorizations) {
    super(StandardMessageCodec.INSTANCE); this.messenger = messenger; this.authorizations = authorizations;
  }
  create(_context: common.Context, viewId: number, args: Any): PlatformView {
    return new HarmonyGallerySaveButton(this.messenger, this.authorizations, viewId, args as Map<string, Object>);
  }
}

class HarmonyGallerySaveButton extends PlatformView {
  private readonly id: number;
  private readonly channel: MethodChannel;
  private readonly authorizations: GallerySaveAuthorizations;
  private disposed = false;
  style: GalleryButtonStyle = { enabled: true, foreground: 0xffffffff, background: 0xff1b242c };
  onStyleChanged?: (style: GalleryButtonStyle) => void;

  constructor(messenger: BinaryMessenger, authorizations: GallerySaveAuthorizations, id: number, args: Map<string, Object>) {
    super(); this.id = id; this.authorizations = authorizations;
    this.configure(args);
    this.channel = new MethodChannel(messenger, 'org.mewx.wenku8/gallery_save_button/' + id);
    this.channel.setMethodCallHandler({ onMethodCall: (call: MethodCall, result: MethodResult): void => {
      if (call.method !== 'configure') { result.notImplemented(); return; }
      if (this.disposed) { result.error('gallery_closed', '保存按钮已关闭', null); return; }
      this.configure(call.args as Map<string, Object>); result.success(null);
    } });
  }

  private configure(args: Map<string, Object>): void {
    if (!args) { return; }
    const foreground = args.get('foreground'); const background = args.get('background');
    this.style = {
      enabled: args.has('enabled') ? args.get('enabled') === true : this.style.enabled,
      foreground: typeof foreground === 'number' ? (foreground | 0xff000000) >>> 0 : this.style.foreground,
      background: typeof background === 'number' ? (background | 0xff000000) >>> 0 : this.style.background,
    };
    this.onStyleChanged?.(this.style);
  }

  clicked(result: SaveButtonOnClickResult): void {
    if (this.disposed || !this.style.enabled) { return; }
    if (result === SaveButtonOnClickResult.SUCCESS) {
      // Close the local double-tap window before Dart starts rendering. Its
      // configure update re-enables this same visible button after completion.
      this.style = { enabled: false, foreground: this.style.foreground, background: this.style.background };
      this.onStyleChanged?.(this.style);
      this.channel.invokeMethod('authorized', new Map<string, Object>([
        ['authorizationToken', this.authorizations.authorized(this.id)],
      ]));
    } else {
      this.authorizations.revoke(this.id);
      this.channel.invokeMethod('authorizationFailed', new Map<string, Object>([
        ['code', 'gallery_permission'], ['message', '未获得相册保存授权，请再次点击“保存图片”并允许保存'],
      ]));
    }
  }

  getView(): WrappedBuilder<[Params]> { return new WrappedBuilder(gallerySaveButtonBuilder); }
  dispose(): void {
    if (this.disposed) { return; }
    this.disposed = true; this.authorizations.revoke(this.id);
    this.channel.setMethodCallHandler(null); this.onStyleChanged = undefined;
  }
}

@Builder
function gallerySaveButtonBuilder(params: Params) {
  GallerySaveButtonComponent({ view: params.platformView as HarmonyGallerySaveButton })
}

@Component
struct GallerySaveButtonComponent {
  view: HarmonyGallerySaveButton | null = null;
  @State buttonEnabled: boolean = true;
  @State buttonForeground: number = 0xffffffff;
  @State buttonBackground: number = 0xff1b242c;

  aboutToAppear(): void {
    const apply = (style: GalleryButtonStyle): void => {
      this.buttonEnabled = style.enabled;
      this.buttonForeground = style.foreground;
      this.buttonBackground = style.background;
    };
    apply(this.view!.style); this.view!.onStyleChanged = apply;
  }
  aboutToDisappear(): void { if (this.view) { this.view.onStyleChanged = undefined; } }
  build() {
    Column() {
      SaveButton({ text: SaveDescription.SAVE_IMAGE, buttonType: ButtonType.Capsule })
        .fontSize(16).fontColor(this.buttonForeground).backgroundColor(this.buttonBackground)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .width('100%').height('100%')
        .onClick((_event: ClickEvent, result: SaveButtonOnClickResult): void => { this.view?.clicked(result); })
    }.width('100%').height('100%').enabled(this.buttonEnabled)
  }
}
