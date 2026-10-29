import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

Widget? harmonyGallerySaveButtonView({
  required bool enabled,
  required Color foreground,
  required Color background,
  required ValueChanged<int> onCreated,
}) => OhosView(
  viewType: 'org.mewx.wenku8/gallery_save_button',
  onPlatformViewCreated: onCreated,
  layoutDirection: TextDirection.ltr,
  creationParams: {
    'enabled': enabled,
    'foreground': foreground.toARGB32(),
    'background': background.toARGB32(),
  },
  creationParamsCodec: const StandardMessageCodec(),
);
