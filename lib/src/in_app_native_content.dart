// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';

import 'in_app_messaging.dart';
import 'in_app_native_text.dart';

/// Converts a validated `#RRGGBB` or `#RRGGBBAA` color.
Color inAppNativeColor(String hex) {
  final rgb = int.parse(hex.substring(1, 7), radix: 16);
  final alpha = hex.length == 9 ? int.parse(hex.substring(7), radix: 16) : 0xFF;
  return Color((alpha << 24) | rgb);
}

/// Draws native content with Flutter widgets, so the message needs no WebView.
class MeiroInAppNativeContent extends StatefulWidget {
  const MeiroInAppNativeContent({required this.display, super.key});

  final MeiroInAppDisplay display;

  @override
  State<MeiroInAppNativeContent> createState() =>
      _MeiroInAppNativeContentState();
}

class _MeiroInAppNativeContentState extends State<MeiroInAppNativeContent> {
  final GlobalKey _body = GlobalKey();
  Map<String, ImageProvider>? _images;

  MeiroInAppDisplay get _display => widget.display;
  Map<String, Object?> get _content => _display.message.nativeContent!;
  List<Map> get _blocks => (_content['blocks'] as List).cast<Map>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  Future<void> _prepare() async {
    if (!mounted) return;
    if (!MeiroInAppNativeText.hasRequiredValues(
      _display.message.requiredProfileAttributes,
      _display.profile,
    )) {
      _display.action('error', {'reason': 'Missing required profile data'});
      return;
    }
    final media = MediaQuery.of(context);
    final maxPixels = (media.size.width * media.devicePixelRatio * 2).round();
    final images = <String, ImageProvider>{
      for (final block in _blocks)
        if (block['type'] == 'image')
          (block['image'] as Map)['url'] as String: ResizeImage(
            NetworkImage((block['image'] as Map)['url'] as String),
            width: maxPixels,
            height: maxPixels,
            policy: ResizeImagePolicy.fit,
            allowUpscaling: false,
          ),
    };
    var failed = false;
    await Future.wait(
      images.values.map(
        (image) =>
            precacheImage(image, context, onError: (_, __) => failed = true),
      ),
    );
    if (!mounted) return;
    if (failed) {
      _display.action('error', {'reason': 'Native image failed to load'});
      return;
    }
    setState(() => _images = images);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportHeight();
      _display.action('ready', const {});
    });
  }

  void _reportHeight() {
    final box = _body.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      _display.action('height', {'height': box.size.height});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_images == null) return const SizedBox.shrink();
    return Material(
      color: inAppNativeColor(_content['backgroundColor'] as String),
      child: SingleChildScrollView(
        primary: false,
        child: NotificationListener<SizeChangedLayoutNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _reportHeight(),
            );
            return true;
          },
          child: SizeChangedLayoutNotifier(
            child: Padding(
              key: _body,
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, block) in _blocks.indexed) ...[
                    if (index > 0) const SizedBox(height: 12),
                    _block(block),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _block(Map block) {
    const inset = EdgeInsets.symmetric(horizontal: 20);
    switch (block['type']) {
      case 'image':
        return Image(
          image: _images![(block['image'] as Map)['url'] as String]!,
          fit: BoxFit.fitWidth,
          semanticLabel: block['accessibilityLabel'] as String,
        );
      case 'text':
        final title = block['style'] == 'title';
        return Padding(
          padding: inset,
          child: Semantics(
            header: title,
            child: Text(
              _render(block['text'] as String),
              style: TextStyle(
                color: inAppNativeColor(block['color'] as String),
                fontSize: title ? 20 : 15,
                fontWeight: title ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      case 'buttons':
        return Padding(
          padding: inset,
          child: Row(
            children: [
              for (final (index, button)
                  in (block['buttons'] as List).cast<Map>().indexed) ...[
                if (index > 0) const SizedBox(width: 8),
                Expanded(child: _button(button)),
              ],
            ],
          ),
        );
      default:
        return SizedBox(height: (block['height'] as int).toDouble());
    }
  }

  Widget _button(Map button) => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor:
              inAppNativeColor(button['backgroundColor'] as String),
          foregroundColor: inAppNativeColor(button['color'] as String),
          minimumSize: const Size(0, 44),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 15),
        ),
        onPressed: () => _press(button),
        child: Text(
          _render(button['label'] as String),
          textAlign: TextAlign.center,
        ),
      );

  String _render(String text) =>
      MeiroInAppNativeText.render(text, _display.profile);

  void _press(Map button) {
    final action = button['action'] as Map;
    final url = action['type'] == 'url' ? action['url'] as String : null;
    _display.action('click', {
      'element': 'button',
      'id': button['id'],
      'url': url,
    });
    if (url == null) {
      _display.action('close', const {});
    } else {
      _display.action('navigate', {'url': url});
    }
  }
}
