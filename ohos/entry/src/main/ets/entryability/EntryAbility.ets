
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import HarmonyDocumentsPlugin from '../plugins/HarmonyDocumentsPlugin';
import HarmonyReaderPlugin from '../plugins/HarmonyReaderPlugin';
import HarmonyNetworkPlugin from '../plugins/HarmonyNetworkPlugin';
import HarmonyLinksPlugin from '../plugins/HarmonyLinksPlugin';
import HarmonySpeechPlugin from '../plugins/HarmonySpeechPlugin';
import HarmonyAudioPlugin from '../plugins/HarmonyAudioPlugin';
import HarmonySecureStoragePlugin from '../plugins/HarmonySecureStoragePlugin';
import HarmonyLanPlugin from '../plugins/HarmonyLanPlugin';
import HarmonyHapticsPlugin from '../plugins/HarmonyHapticsPlugin';
import HarmonyBookOpenInbox from '../plugins/HarmonyBookOpenInbox';
import ReadingWidgetsPlugin from '../readingwidgets/ReadingWidgetsPlugin';
import ReadingWidgetOpenInbox from '../readingwidgets/ReadingWidgetOpenInbox';
import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';

export default class EntryAbility extends FlutterAbility {
  private reader?: HarmonyReaderPlugin;
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.receiveReadingWidget(want);
    this.receiveBook(want);
    super.onCreate(want, launchParam);
  }
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.receiveReadingWidget(want);
    this.receiveBook(want);
    super.onNewWant(want, launchParam);
  }
  private receiveBook(want: Want): void {
    if (want.uri) { HarmonyBookOpenInbox.offer(want.uri); }
  }
  private receiveReadingWidget(want: Want): void {
    const destination = want.parameters?.['readingWidgetDestination'];
    if (typeof destination === 'string') { ReadingWidgetOpenInbox.offer(destination); }
    else {
      const id = want.parameters?.['ohos.extra.param.key.form_identity'];
      if (id !== undefined && /^[0-9]{1,32}$/.test(String(id))) { ReadingWidgetOpenInbox.offer('configure:' + String(id)); }
    }
  }
  onForeground(): void { this.reader?.setForeground(true); super.onForeground(); }
  onBackground(): void { this.reader?.setForeground(false); super.onBackground(); }
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    flutterEngine.getPlugins()?.add(new HarmonyDocumentsPlugin(this.context))
    this.reader = new HarmonyReaderPlugin(this.context)
    flutterEngine.getPlugins()?.add(this.reader)
    flutterEngine.getPlugins()?.add(new HarmonyNetworkPlugin())
    flutterEngine.getPlugins()?.add(new HarmonyLinksPlugin(this.context))
    flutterEngine.getPlugins()?.add(new HarmonySpeechPlugin(this.context))
    flutterEngine.getPlugins()?.add(new HarmonyAudioPlugin(this.context))
    flutterEngine.getPlugins()?.add(new HarmonySecureStoragePlugin())
    flutterEngine.getPlugins()?.add(new HarmonyLanPlugin(this.context))
    flutterEngine.getPlugins()?.add(new HarmonyHapticsPlugin(this.context))
    flutterEngine.getPlugins()?.add(new ReadingWidgetsPlugin())
  }
}
