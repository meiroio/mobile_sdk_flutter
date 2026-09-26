// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'in_app_messaging.dart';

/// A named container for an inline in-app message or story rail.
class MeiroInAppMessageView extends StatefulWidget {
  /// Mounts a named placement in the app layout.
  const MeiroInAppMessageView(
      {required this.placement, required this.messaging, super.key});

  /// Exact placement name configured in Pipes.
  final String placement;

  /// Enabled SDK messaging service.
  final MeiroInAppMessaging? messaging;

  @override
  State<MeiroInAppMessageView> createState() => MeiroInAppMessageViewState();
}

class MeiroInAppMessageViewState extends State<MeiroInAppMessageView> {
  MeiroInAppDisplay? display;

  @override
  void initState() {
    super.initState();
    widget.messaging?.register(widget.placement, this);
  }

  @override
  void didUpdateWidget(MeiroInAppMessageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.placement != widget.placement ||
        oldWidget.messaging != widget.messaging) {
      oldWidget.messaging?.unregister(oldWidget.placement, this);
      display = null;
      widget.messaging?.register(widget.placement, this);
    }
  }

  @override
  void dispose() {
    widget.messaging?.unregister(widget.placement, this);
    super.dispose();
  }

  void show(MeiroInAppDisplay? next) {
    if (mounted) setState(() => display = next);
  }

  bool get isFullyVisible {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    final screen = MediaQuery.sizeOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final scrollBox = Scrollable.maybeOf(context)?.context.findRenderObject();
    final scrollOrigin = scrollBox is RenderBox
        ? scrollBox.localToGlobal(Offset.zero)
        : Offset.zero;
    final scrollSize = scrollBox is RenderBox ? scrollBox.size : screen;
    return size.width > 0 &&
        size.height > 1 &&
        origin.dx >= 0 &&
        origin.dy >= 0 &&
        origin.dx + size.width <= screen.width &&
        origin.dy + size.height <= screen.height - keyboard &&
        origin.dx >= scrollOrigin.dx &&
        origin.dy >= scrollOrigin.dy &&
        origin.dx + size.width <= scrollOrigin.dx + scrollSize.width &&
        origin.dy + size.height <= scrollOrigin.dy + scrollSize.height;
  }

  @override
  Widget build(BuildContext context) {
    final current = display;
    if (current == null) return const SizedBox.shrink();
    return ValueListenableBuilder<double>(
      valueListenable: current.height,
      builder: (context, height, _) => SizedBox(
        height: height,
        width: double.infinity,
        child: ValueListenableBuilder<bool>(
          valueListenable: current.visible,
          builder: (context, visible, _) => Opacity(
            opacity: visible ? 1 : 0,
            child: MeiroInAppContent(
                key: ValueKey(current.identity), display: current),
          ),
        ),
      ),
    );
  }
}

/// Web content bridge shared by modal, sticky, inline, and story player views.
class MeiroInAppContent extends StatefulWidget {
  const MeiroInAppContent({required this.display, super.key});

  final MeiroInAppDisplay display;

  @override
  State<MeiroInAppContent> createState() => _MeiroInAppContentState();
}

class _MeiroInAppContentState extends State<MeiroInAppContent> {
  static const int _maxBridgeMessageLength = 262144;

  late final WebViewController controller;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      // Native SDK WebViews do not zoom; webview_flutter enables pinch zoom by default.
      ..enableZoom(false)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          if (request.url == 'about:blank') return NavigationDecision.navigate;
          if (request.isMainFrame) {
            widget.display.action('navigate', {'url': request.url});
          }
          return NavigationDecision.prevent;
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true) {
            widget.display.action('error', {'reason': error.description});
          }
        },
        onPageFinished: (_) => _prepare(),
      ));
    widget.display.controller = controller;
    _initialize();
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: controller);

  Future<void> _initialize() async {
    try {
      await controller.addJavaScriptChannel('MeiroInAppNative',
          onMessageReceived: _receive);
      if (!mounted) return;
      await controller.loadHtmlString(
          '<!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="frame-src \'none\'; object-src \'none\'; base-uri \'none\'; form-action \'none\'"></head><body></body></html>');
    } catch (error) {
      widget.display.action('error', {'reason': error.toString()});
    }
  }

  Future<void> _prepare() async {
    try {
      final runtime = await rootBundle
          .loadString('packages/meiro_sdk/assets/in_app_runtime.js');
      if (!mounted) return;
      await controller.runJavaScript(runtime);
      final input = {
        'displayId': widget.display.id,
        'html': widget.display.message.html,
        'survey': widget.display.message.survey,
        'storyCollection': widget.display.message.storyCollection,
        'profile': widget.display.profile,
        'requiredProfileAttributes':
            widget.display.message.requiredProfileAttributes,
        if (widget.display.storyMode != null)
          'storyMode': widget.display.storyMode,
        if (widget.display.storyGroupIndex != null)
          'storyGroupIndex': widget.display.storyGroupIndex,
      };
      await controller
          .runJavaScript('window.MeiroInApp.prepare(${jsonEncode(input)});');
    } catch (error) {
      widget.display.action('error', {'reason': error.toString()});
    }
  }

  void _receive(JavaScriptMessage message) {
    if (message.message.length > _maxBridgeMessageLength) return;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map ||
          decoded['displayId'] != widget.display.id ||
          decoded['kind'] is! String ||
          decoded['data'] is! Map) {
        return;
      }
      widget.display.action(decoded['kind'] as String,
          (decoded['data'] as Map).cast<String, Object?>());
    } catch (_) {/* Ignore malformed creative messages. */}
  }
}
