// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'configuration.dart';
import 'event.dart';
import 'in_app_message.dart';
import 'in_app_message_view.dart';

/// One prepared delivery, including its captured identity and display ID.
class MeiroInAppDisplay {
  MeiroInAppDisplay(
      {required this.message,
      required this.userId,
      required this.sessionId,
      required this.screenName,
      required this.profile,
      required this.onAction,
      String? displayId,
      this.storyMode,
      this.storyGroupIndex})
      : id = displayId ?? const Uuid().v4(),
        identity = const Uuid().v4();

  final MeiroInAppMessage message;
  final String id;
  final String identity;
  final String userId;
  final String sessionId;
  final String screenName;
  final Map<String, Object?> profile;
  final String? storyMode;
  final int? storyGroupIndex;
  final void Function(MeiroInAppDisplay, String, Map<String, Object?>) onAction;
  final ValueNotifier<double> height = ValueNotifier(1);
  final ValueNotifier<bool> visible = ValueNotifier(false);
  final Completer<bool> prepared = Completer<bool>();
  WebViewController? controller;
  String? reservationToken;
  DateTime? reservationDeadline;
  bool hasImpression = false;
  bool disposed = false;

  void action(String kind, Map<String, Object?> data) {
    if (!disposed) onAction(this, kind, data);
  }

  void dispose() {
    disposed = true;
    if (!prepared.isCompleted) prepared.complete(false);
    height.dispose();
    visible.dispose();
  }
}

class _Occurrence {
  _Occurrence(this.type, this.name, this.properties, this.context, this.userId,
      this.sessionId, this.generation, this.time);
  final String type;
  final String? name;
  final Map<String, Object?> properties;
  final Map<String, Object?> context;
  final String userId;
  final String sessionId;
  final int generation;
  final DateTime time;
}

/// Delivers v2 Pipes in-app messages for the current Flutter SDK identity.
class MeiroInAppMessaging {
  static const int _maxPendingOccurrences = 32;
  static const int _maxNavigationUrlLength = 2048;
  static const int _commitAttempts = 3;
  static const Duration _preparationTimeout = Duration(seconds: 15);
  static const Duration _visibilityPoll = Duration(milliseconds: 250);
  static const Duration _reservationWindow = Duration(seconds: 20);
  static const Duration _commitRetryDelay = Duration(seconds: 1);

  /// Creates the delivery coordinator with SDK identity and transport services.
  MeiroInAppMessaging(
      {required MeiroInAppStore store,
      required MeiroConfiguration configuration,
      required String? appVersion,
      required String Function() userId,
      required String Function() sessionId,
      required Future<void> Function(
              MeiroEventType, Map<String, Object?>, String, String)
          emit,
      required MeiroLogger logger})
      : _store = store,
        _configuration = configuration,
        _appVersion = appVersion,
        _userId = userId,
        _sessionId = sessionId,
        _emit = emit,
        _logger = logger;

  final MeiroInAppStore _store;
  final MeiroConfiguration _configuration;
  final String? _appVersion;
  final String Function() _userId;
  final String Function() _sessionId;
  final Future<void> Function(
      MeiroEventType, Map<String, Object?>, String, String) _emit;
  final MeiroLogger _logger;
  final Map<String, MeiroInAppMessageViewState> _placements = {};
  final Map<String, MeiroInAppDisplay> _slots = {};
  final Map<String, _Occurrence> _waiting = {};
  final Map<String, int> _busySlots = {};
  Completer<void> _cancellation = Completer<void>();
  final List<_Occurrence> _pending = [];
  final Random _random = Random();
  OverlayEntry? _overlayEntry;
  MeiroInAppDisplay? _overlay;
  MeiroInAppDisplay? _player;
  bool _active = true;
  bool _enabled = true;
  bool _paused = false;
  bool _fetching = true;
  bool _started = false;
  int _generation = 0;
  int _refreshGeneration = 0;
  String _screen = '';
  String _lastSession = '';

  /// Called with delivery diagnostics, without profile values.
  void Function(String)? onDiagnostic;

  /// Loads cached configuration and refreshes it from Pipes.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _store.loadCache();
    await foreground();
  }

  /// Refreshes configuration and handles a new SDK session.
  Future<void> foreground() async {
    if (!_started) return;
    _active = true;
    _fetching = true;
    final refresh = ++_refreshGeneration;
    final currentSession = _sessionId();
    if (currentSession != _lastSession) {
      _lastSession = currentSession;
      _trigger('session_start', null, const {});
    }
    try {
      await _store.refresh();
    } catch (error) {
      _diagnostic('Configuration refresh failed: $error');
    }
    if (refresh != _refreshGeneration) return;
    _fetching = false;
    final waiting = List<_Occurrence>.of(_pending);
    _pending.clear();
    for (final occurrence in waiting) {
      _process(occurrence);
    }
  }

  /// Cancels pending work when the app backgrounds.
  void background() {
    _active = false;
    _removePlayer(reason: 'app_background');
    if (_overlay?.message.format == 'sticky') _remove(_overlay!);
    _cancelPending();
  }

  /// Prevents new displays without dismissing current content.
  void pause() {
    _paused = true;
    _cancelPending();
  }

  /// Allows future triggers; discarded triggers are not replayed.
  void resume() {
    _paused = false;
  }

  /// Dismisses the active overlay when Android sends a system Back event.
  bool dismissOnBack() {
    final player = _player;
    if (player != null) {
      _removePlayer(reason: 'back');
      return true;
    }
    final display = _overlay;
    if (display == null || !display.visible.value) return false;
    _close(display, 'back', trackClick: false);
    return true;
  }

  /// Mirrors global SDK tracking enablement.
  void setEnabled(bool enabled) {
    _enabled = enabled;
    if (!enabled) _cancelPending();
  }

  /// Removes content captured under the previous mobile identity.
  void reset() {
    _cancelPending();
    _lastSession = '';
    _removePlayer(reason: 'reset');
    for (final display in List<MeiroInAppDisplay>.of(_slots.values)) {
      _remove(display);
    }
  }

  /// Sends a named event trigger using the event's properties.
  void trackEvent(Map<String, Object?> properties) {
    _trigger(
        'event',
        properties['name'] is String ? properties['name'] as String : null,
        properties);
  }

  /// Sends a screen trigger and cancels older pending screen work.
  void trackScreen(String name) {
    if (_screen != name) {
      if (_overlay?.message.format == 'sticky') _remove(_overlay!);
      _screen = name;
      _cancelPending();
    }
    _trigger('screen_view', name, const {});
  }

  /// Registers one visible inline placement.
  void register(String placement, MeiroInAppMessageViewState view) {
    if (_placements.containsKey(placement) && _placements[placement] != view) {
      _diagnostic('Placement is already mounted: $placement');
      return;
    }
    _placements[placement] = view;
    final waiting = _waiting.remove(placement);
    if (waiting != null) _process(waiting, onlySlot: placement);
  }

  /// Unregisters an inline placement when its widget leaves the tree.
  void unregister(String placement, MeiroInAppMessageViewState view) {
    if (_placements[placement] != view) return;
    _placements.remove(placement);
    _waiting.remove(placement);
    final display = _slots[placement];
    if (display != null) _remove(display);
  }

  /// Releases all mounted and pending resources.
  void dispose() {
    _active = false;
    reset();
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
    _store.dispose();
  }

  void _trigger(String type, String? name, Map<String, Object?> properties) {
    if (!_active || !_enabled || _paused) return;
    final occurrence = _Occurrence(
        type,
        name,
        properties,
        {
          'screen': _screen,
          'event': properties,
          'app_id': _configuration.appId,
          'platform': Platform.operatingSystem,
          'app_version': _appVersion,
          'language':
              _configuration.language ?? Platform.localeName.split('_').first
        },
        _userId(),
        _sessionId(),
        _generation,
        DateTime.now());
    if (_fetching) {
      if (_pending.length < _maxPendingOccurrences) _pending.add(occurrence);
    } else {
      _process(occurrence);
    }
  }

  void _process(_Occurrence occurrence, {String? onlySlot}) {
    if (!_valid(occurrence) || !_store.isFresh) return;
    final groups = <String, List<MeiroInAppMessage>>{};
    for (final message in _store.messages) {
      if (message.trigger['type'] != occurrence.type ||
          (message.trigger['name'] != null &&
              message.trigger['name'] != occurrence.name)) {
        continue;
      }
      final slot =
          message.format == 'inline' ? message.placement! : '__overlay';
      groups.putIfAbsent(slot, () => []).add(message);
    }
    for (final entry in groups.entries) {
      final slot = entry.key;
      if (onlySlot != null && slot != onlySlot) continue;
      if (slot == '__overlay' && (_overlay != null || _player != null)) {
        continue;
      }
      if (slot != '__overlay' && !_placements.containsKey(slot)) {
        if (_waiting.length < _maxPendingOccurrences) {
          _waiting[slot] = occurrence;
        }
        continue;
      }
      if (_slots.containsKey(slot) || _busySlots.containsKey(slot)) continue;
      final candidates = entry.value.toList()
        ..shuffle(_random)
        ..sort((a, b) {
          final priority = b.priority.compareTo(a.priority);
          return priority != 0
              ? priority
              : _store.shown(a).compareTo(_store.shown(b));
        });
      _busySlots[slot] = occurrence.generation;
      unawaited(
          _deliver(slot, candidates, occurrence).catchError((Object error) {
        _diagnostic('Delivery failed: $error');
      }).whenComplete(() {
        if (_busySlots[slot] == occurrence.generation) _busySlots.remove(slot);
      }));
    }
  }

  Future<void> _deliver(String slot, List<MeiroInAppMessage> candidates,
      _Occurrence occurrence) async {
    for (final message in candidates) {
      if (!_valid(occurrence) || !_store.isFresh || _slots.containsKey(slot)) {
        return;
      }
      if (!_store.eligible(message, occurrence.sessionId)) continue;
      final delay = Duration(
          milliseconds:
              ((message.trigger['delaySeconds'] as num) * 1000).round());
      final remaining = delay - DateTime.now().difference(occurrence.time);
      if (remaining > Duration.zero) {
        await Future.any<void>([
          Future<void>.delayed(remaining),
          _cancellation.future,
        ]);
      }
      if (!_valid(occurrence)) return;
      Map<String, Object?> profile = {};
      if (message.needsProfile) {
        try {
          profile = await _store.profile(occurrence.userId);
        } catch (_) {
          _diagnostic('Profile lookup failed');
          continue;
        }
      }
      if (!_valid(occurrence) ||
          !MeiroInAppRules.matches(
              message.conditions, occurrence.context, profile)) {
        continue;
      }
      final display = MeiroInAppDisplay(
          message: message,
          userId: occurrence.userId,
          sessionId: occurrence.sessionId,
          screenName: occurrence.context['screen'] as String,
          profile: profile,
          onAction: _onAction);
      _slots[slot] = display;
      if (slot == '__overlay') {
        if (!_mountOverlay(display)) {
          _remove(display);
          continue;
        }
      } else {
        _placements[slot]?.show(display);
      }
      final ready = await display.prepared.future
          .timeout(_preparationTimeout, onTimeout: () => false);
      if (!ready || !_valid(occurrence) || display.disposed) {
        _remove(display);
        continue;
      }
      if (slot == '__overlay') {
        if (await _admit(display) && _valid(occurrence) && !display.disposed) {
          display.visible.value = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!display.disposed) _impression(display);
          });
          return;
        }
      } else {
        final view = _placements[slot];
        while (!display.disposed &&
            _valid(occurrence) &&
            view != null &&
            !view.isFullyVisible) {
          await Future<void>.delayed(_visibilityPoll);
        }
        final admitted =
            !display.disposed && _valid(occurrence) && await _admit(display);
        if (admitted &&
            !display.disposed &&
            _valid(occurrence) &&
            view?.isFullyVisible == true &&
            _overlay == null &&
            _player == null) {
          display.visible.value = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!display.disposed &&
                view?.isFullyVisible == true &&
                _overlay == null &&
                _player == null) {
              _impression(display);
            }
          });
          return;
        }
      }
      _remove(display);
    }
  }

  bool _mountOverlay(MeiroInAppDisplay display) {
    final overlay = _configuration.navigatorKey?.currentState?.overlay;
    if (overlay == null) {
      _diagnostic('Navigator key is not mounted');
      return false;
    }
    _overlay = display;
    _overlayEntry = OverlayEntry(builder: (context) => _overlayWidget(display));
    overlay.insert(_overlayEntry!);
    return true;
  }

  Widget _overlayWidget(MeiroInAppDisplay display) {
    final screen =
        MediaQuery.sizeOf(_configuration.navigatorKey!.currentContext!);
    final sticky = display.message.format == 'sticky';
    final player = display.storyMode == 'player';
    // Sticky banners float as a card, matching the native SDKs.
    final margin = sticky ? 10.0 : 0.0;
    final maxHeight = sticky
        ? (screen.height - 2 * margin) *
            ((display.message.stickyBanner!['maxHeightPercent'] as num) / 100)
        : screen.height * 0.8;
    return ValueListenableBuilder<bool>(
        valueListenable: display.visible,
        builder: (context, visible, _) => BlockSemantics(
            blocking: visible && !sticky,
            child: Stack(children: [
              if (!sticky)
                Positioned.fill(
                    child: IgnorePointer(
                        ignoring: !visible,
                        child: GestureDetector(
                          onTap: player
                              ? null
                              : () =>
                                  _close(display, 'outside', trackClick: false),
                          child: _scrim(visible: visible, player: player),
                        ))),
              Align(
                alignment: player
                    ? Alignment.center
                    : sticky &&
                            display.message.stickyBanner!['position'] == 'top'
                        ? Alignment.topCenter
                        : sticky
                            ? Alignment.bottomCenter
                            : Alignment.center,
                child: SafeArea(
                    minimum: EdgeInsets.all(margin),
                    child: IgnorePointer(
                        ignoring: !visible,
                        child: Opacity(
                          opacity: visible ? 1 : 0,
                          child: Material(
                            color: player ? Colors.black : Colors.white,
                            elevation: sticky ? 6 : 0,
                            borderRadius:
                                player ? null : BorderRadius.circular(12),
                            clipBehavior: Clip.antiAlias,
                            child: SizedBox(
                                width: sticky
                                    ? screen.width - 2 * margin
                                    : screen.width * (player ? 1 : 0.9),
                                height: player
                                    ? screen.height
                                    : min(display.height.value + 48, maxHeight),
                                child: Column(children: [
                                  if (!player)
                                    SizedBox(
                                        height: 48,
                                        child: Align(
                                            alignment: Alignment.centerRight,
                                            child: IconButton(
                                                tooltip: 'Close message',
                                                icon: const Icon(Icons.close),
                                                onPressed: () => _close(
                                                    display, 'close_button')))),
                                  Expanded(
                                      child: MeiroInAppContent(
                                          key: ValueKey(display.identity),
                                          display: display)),
                                ])),
                          ),
                        ))),
              ),
            ])));
  }

  /// Keeps system bar icons readable above the black story player. Only this
  /// leaf changes shape, so the WebView subtree is never remounted.
  Widget _scrim({required bool visible, required bool player}) {
    if (!visible) return const ColoredBox(color: Colors.transparent);
    if (!player) return const ColoredBox(color: Colors.black54);
    return const AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: ColoredBox(color: Colors.black));
  }

  Future<bool> _admit(MeiroInAppDisplay display) async {
    if (display.disposed || !_enabled || !_active || _paused) return false;
    final deadline = DateTime.now().add(_reservationWindow);
    try {
      final response = await _store.frequency(
          display.message, display.id, display.userId, 'reserve');
      if (response['decision'] == 'notEnforced') return true;
      if (response['decision'] != 'reserved' ||
          response['reservationToken'] is! String) {
        return false;
      }
      display.reservationToken = response['reservationToken'] as String;
      display.reservationDeadline = deadline;
      return true;
    } catch (error) {
      _diagnostic('Frequency policy check failed: $error');
      return false;
    }
  }

  void _impression(MeiroInAppDisplay display) {
    if (display.disposed ||
        display.hasImpression ||
        !_active ||
        !_enabled ||
        _paused) {
      return;
    }
    final deadline = display.reservationDeadline;
    if (deadline != null && !DateTime.now().isBefore(deadline)) {
      _remove(display);
      return;
    }
    display.hasImpression = true;
    _store.impression(display.message, display.sessionId);
    _track(MeiroEventType.inAppMessageImpression, display, {});
    if (display.reservationToken != null) unawaited(_confirm(display));
  }

  Future<void> _confirm(MeiroInAppDisplay display) async {
    for (var attempt = 0; attempt < _commitAttempts; attempt++) {
      final deadline = display.reservationDeadline;
      if (deadline != null && !DateTime.now().isBefore(deadline)) break;
      try {
        final response = await _store.frequency(display.message, display.id,
            display.userId, 'commit', display.reservationToken);
        if (response['committed'] == true) return;
      } catch (_) {/* Retry while the server lease remains valid. */}
      await Future<void>.delayed(_commitRetryDelay);
    }
    _diagnostic('Display confirmation is uncertain; capacity remains reserved');
  }

  void _onAction(
      MeiroInAppDisplay display, String kind, Map<String, Object?> data) {
    if (kind == 'ready') {
      if (!display.prepared.isCompleted) display.prepared.complete(true);
      return;
    }
    if (kind == 'error') {
      if (!display.prepared.isCompleted) {
        display.prepared.complete(false);
      } else {
        _remove(display);
      }
      _diagnostic('Creative failed: ${data['reason']}');
      return;
    }
    if (kind == 'height') {
      final height = data['height'];
      if (height is num && height.isFinite && height > 0) {
        display.height.value = height.toDouble();
        _overlayEntry?.markNeedsBuild();
      }
      return;
    }
    if (kind == 'profile') {
      unawaited(_profileResult(display, data['requestId']));
      return;
    }
    if (kind == 'story_open') {
      unawaited(_openStory(display, data));
      return;
    }
    if (kind.startsWith('story_')) {
      final type = {
        'story_view': MeiroEventType.inAppStoryView,
        'story_complete': MeiroEventType.inAppStoryComplete,
        'story_click': MeiroEventType.inAppStoryClick,
        'story_close': MeiroEventType.inAppStoryClose
      }[kind];
      if (type != null && _player == display) _track(type, display, data);
      if (kind == 'story_close') _removePlayer();
      return;
    }
    switch (kind) {
      case 'click':
        _track(MeiroEventType.inAppMessageClick, display, data);
      case 'submit':
        _track(MeiroEventType.inAppMessageSubmit, display, data);
      case 'survey_answer':
        _track(MeiroEventType.surveyAnswer, display,
            {...data, 'response_id': const Uuid().v4()});
      case 'close':
        _close(display, 'custom_close', trackClick: false);
      case 'action':
        if (display.message.format == 'sticky') {
          _close(display, 'action', trackClick: false);
        }
      case 'navigate':
        unawaited(_navigate(display, data['url']));
    }
  }

  Future<void> _profileResult(
      MeiroInAppDisplay display, Object? requestId) async {
    if (requestId is! int || display.controller == null) return;
    try {
      final profile = await _store.profile(display.userId);
      if (!display.disposed) {
        await display.controller!.runJavaScript(
            'window.MeiroInApp.profileResult($requestId, ${_encode(profile)});');
      }
    } catch (_) {
      if (!display.disposed) {
        await display.controller!.runJavaScript(
            'window.MeiroInApp.profileResult($requestId, null, "Profile lookup failed");');
      }
    }
  }

  Future<void> _navigate(MeiroInAppDisplay display, Object? raw) async {
    if (raw is! String || raw.length > _maxNavigationUrlLength) return;
    final url = Uri.tryParse(raw);
    final scheme = url?.scheme.toLowerCase();
    const blocked = {
      'http',
      'javascript',
      'data',
      'file',
      'about',
      'vbscript',
      'blob'
    };
    final allowed = (scheme == 'https' && url?.host.isNotEmpty == true) ||
        (scheme != null && scheme.isNotEmpty && !blocked.contains(scheme));
    if (!allowed || url == null) {
      _diagnostic('Blocked navigation URL');
      return;
    }
    bool opened;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (opened) {
      if (_player == display) {
        _removePlayer(reason: 'action');
      } else if (display.message.format == 'sticky') {
        _close(display, 'action', trackClick: false);
      } else if (display.message.format == 'modal') {
        _remove(display);
      }
    }
  }

  Future<void> _openStory(
      MeiroInAppDisplay rail, Map<String, Object?> data) async {
    final index = data['groupIndex'];
    final groups = rail.message.storyCollection?['groups'];
    if (!rail.hasImpression ||
        index is! int ||
        groups is! List ||
        index < 0 ||
        index >= groups.length ||
        _overlay != null ||
        _player != null) {
      return;
    }
    final player = MeiroInAppDisplay(
        message: rail.message,
        userId: rail.userId,
        sessionId: rail.sessionId,
        screenName: rail.screenName,
        profile: {},
        displayId: rail.id,
        storyMode: 'player',
        storyGroupIndex: index,
        onAction: _onAction);
    _player = player;
    if (!_mountOverlay(player)) {
      _player = null;
      return;
    }
    final ready = await player.prepared.future
        .timeout(_preparationTimeout, onTimeout: () => false);
    if (!ready || player.disposed) {
      _removePlayer();
      return;
    }
    player.visible.value = true;
    _track(MeiroEventType.inAppStoryGroupOpen, player,
        {'group_id': data['groupId'], 'group_index': index});
  }

  void _removePlayer({String? reason}) {
    final player = _player;
    if (player == null) return;
    if (reason != null && player.visible.value) {
      _track(MeiroEventType.inAppStoryClose, player, {'reason': reason});
    }
    _player = null;
    _remove(player);
  }

  void _close(MeiroInAppDisplay display, String reason,
      {bool trackClick = true}) {
    if (trackClick) {
      _track(MeiroEventType.inAppMessageClick, display,
          {'element': 'button', 'id': 'close'});
    }
    _track(MeiroEventType.inAppMessageClose, display, {'reason': reason});
    _remove(display);
  }

  void _remove(MeiroInAppDisplay display) {
    if (display.disposed) return;
    if (!display.hasImpression && display.reservationToken != null) {
      unawaited(_store
          .frequency(display.message, display.id, display.userId, 'release',
              display.reservationToken)
          .then((_) {}, onError: (_) {}));
    }
    final slot =
        display.message.format == 'inline' && display.storyMode != 'player'
            ? display.message.placement!
            : '__overlay';
    if (_slots[slot] == display) _slots.remove(slot);
    if (_overlay == display) {
      _overlay = null;
      _overlayEntry?.remove();
      _overlayEntry?.dispose();
      _overlayEntry = null;
    }
    if (_player == display) _player = null;
    if (slot != '__overlay') _placements[slot]?.show(null);
    display.dispose();
  }

  void _track(MeiroEventType type, MeiroInAppDisplay display,
      Map<String, Object?> data) {
    final payload = <String, Object?>{
      ...type.id.startsWith('in_app_story_') ? _storyData(display, data) : data,
      'message_id': display.message.id,
      'message_version': display.message.version,
      'display_id': display.id,
      'occurrence_id': const Uuid().v4(),
      'format': display.message.format,
      'placement': display.message.placement,
      'screen_name': display.screenName
    };
    unawaited(_emit(type, payload, display.userId, display.sessionId));
  }

  Map<String, Object?> _storyData(
      MeiroInAppDisplay display, Map<String, Object?> data) {
    final result = Map<String, Object?>.of(data);
    const names = {
      'groupId': 'group_id',
      'groupIndex': 'group_index',
      'storyId': 'story_id',
      'storyIndex': 'story_index',
    };
    for (final entry in names.entries) {
      if (result.containsKey(entry.key)) {
        result[entry.value] = result.remove(entry.key);
      }
    }
    final groups = display.message.storyCollection?['groups'];
    final index = display.storyGroupIndex;
    if (groups is List &&
        index != null &&
        index >= 0 &&
        index < groups.length) {
      final group = groups[index];
      if (group is Map && group['id'] is String) {
        result['group_id'] = group['id'];
      }
    }
    return result;
  }

  bool _valid(_Occurrence occurrence) =>
      _active &&
      _enabled &&
      !_paused &&
      occurrence.generation == _generation &&
      occurrence.userId == _userId() &&
      occurrence.sessionId == _sessionId();

  void _cancelPending() {
    _generation++;
    _cancellation.complete();
    _cancellation = Completer<void>();
    _busySlots.clear();
    _pending.clear();
    _waiting.clear();
    for (final display in List<MeiroInAppDisplay>.of(_slots.values)) {
      if (!display.hasImpression) _remove(display);
    }
  }

  void _diagnostic(String reason) {
    _logger.log(reason);
    onDiagnostic?.call(reason);
  }

  String _encode(Object? value) =>
      value == null ? 'null' : const JsonEncoder().convert(value);
}
