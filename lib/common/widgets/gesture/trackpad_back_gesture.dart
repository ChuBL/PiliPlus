import 'dart:math' show max;

import 'package:PiliPlus/common/widgets/gesture/horizontal_drag_gesture_recognizer.dart';
import 'package:PiliPlus/utils/share_utils.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// iPadOS trackpad: a two-finger swipe to the right that no inner widget
/// claims (e.g. a [TabBarView] or a horizontal list) goes back.
///
/// If the current page can be popped, this drives an interactive, cancelable
/// back gesture, like the iOS edge swipe. If going back only closes something
/// inside the page (a local history entry, e.g. a bottom sheet on the video
/// page), the swipe acts like pressing the back button once, see [onBack].
/// Pages that veto popping (e.g. multi-select mode) are left alone.
///
/// The edge swipe of [CupertinoRouteTransitionMixin] only listens to
/// [PointerDownEvent]s, which a trackpad pan never produces.
class TrackpadBackGesture extends StatefulWidget {
  const TrackpadBackGesture({
    super.key,
    required this.onBack,
    required this.child,
  });

  final VoidCallback onBack;

  final Widget child;

  static bool enabled = false;

  static Future<void> init() async {
    enabled = await ShareUtils.isIpad;
  }

  static (int, Duration)? _blocked;

  /// Called by widgets that handle trackpad pans with a raw [Listener] (which
  /// does not take part in the gesture arena), e.g. seeking on the video
  /// player, so that such pans never start a back gesture.
  ///
  /// Pointer events are dispatched along the hit test path from the deepest
  /// target, so this always runs before [TrackpadBackGesture] sees the event.
  static void block(PointerPanZoomStartEvent event) {
    _blocked = (event.pointer, event.timeStamp);
  }

  static bool _consumeBlocked(PointerPanZoomStartEvent event) {
    final blocked = _blocked == (event.pointer, event.timeStamp);
    _blocked = null;
    return blocked;
  }

  @override
  State<TrackpadBackGesture> createState() => _TrackpadBackGestureState();
}

class _TrackpadBackGestureState extends State<TrackpadBackGesture> {
  late final _TrackpadBackDragGestureRecognizer _recognizer;
  _BackGestureController? _backGestureController;

  @override
  void initState() {
    super.initState();
    _recognizer = _TrackpadBackDragGestureRecognizer(debugOwner: this)
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel;
  }

  @override
  void dispose() {
    _recognizer.dispose();
    // If this is disposed during a drag, call navigator.didStopUserGesture.
    final navigator = _backGestureController?.navigator;
    _backGestureController = null;
    if (navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted) navigator.didStopUserGesture();
      });
    }
    super.dispose();
  }

  static (PageRoute, _BackMode)? get _currentBackMode {
    if (SmartDialog.checkExist()) return null;
    final route = Get.routing.route;
    if (route is! PageRoute ||
        !route.isCurrent ||
        route.isFirst ||
        !route.animation!.isCompleted ||
        route.navigator!.userGestureInProgress) {
      return null;
    }
    if (route.popGestureEnabled) {
      return (route, .interactive);
    }
    if (route.willHandlePopInternally) {
      return (route, .button);
    }
    return null;
  }

  void _handlePointerPanZoomStart(PointerPanZoomStartEvent event) {
    if (TrackpadBackGesture._consumeBlocked(event)) return;
    if (_currentBackMode != null) {
      _recognizer.addPointerPanZoom(event);
    }
  }

  void _handleDragStart(DragStartDetails details) {
    assert(_backGestureController == null);
    switch (_currentBackMode) {
      case (final route, _BackMode.interactive):
        _backGestureController = _BackGestureController(route);
      case (_, _BackMode.button):
        widget.onBack();
      case null:
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _backGestureController?.dragUpdate(
      details.primaryDelta! / context.size!.width,
    );
  }

  void _handleDragEnd(DragEndDetails details) {
    _backGestureController?.dragEnd(
      details.velocity.pixelsPerSecond.dx / context.size!.width,
    );
    _backGestureController = null;
  }

  void _handleDragCancel() {
    _backGestureController?.dragEnd(0.0);
    _backGestureController = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerPanZoomStart: _handlePointerPanZoomStart,
      child: widget.child,
    );
  }
}

enum _BackMode {
  /// the page follows the fingers, like the iOS edge swipe
  interactive,

  /// same as pressing the back button once
  button,
}

class _TrackpadBackDragGestureRecognizer extends HorizontalDragGestureRecognizer
    with InitialPositionMixin {
  _TrackpadBackDragGestureRecognizer({super.debugOwner})
    : super(supportedDevices: const {PointerDeviceKind.trackpad});

  /// Larger than the slop of any inner horizontal drag recognizer
  /// ([CustomHorizontalDragGestureRecognizer] uses [touchSlopH], others
  /// [kTouchSlop], scale recognizers [kPanSlop]), so that inner widgets
  /// always win the arena first and this only acts as a fallback.
  static double get _slop => max(touchSlopH, kPanSlop) + 6.0;

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    // rightward only, and at least as strict as the angle check of
    // [CustomHorizontalDragGestureRecognizer].
    final offset = lastPosition.global - initialPosition!;
    return globalDistanceMoved > _slop && offset.dx.abs() > offset.dy.abs() * 3;
  }
}

/// Mirrors the private `_CupertinoBackGestureController` of `cupertino_ui`.
///
/// Works in logical coordinates: 0.0 is the page dismissed, 1.0 is the page
/// on top.
class _BackGestureController {
  _BackGestureController(PageRoute route)
    : navigator = route.navigator!,
      // ignore: invalid_use_of_protected_member
      controller = route.controller!,
      getIsCurrent = (() => route.isCurrent),
      getIsActive = (() => route.isActive) {
    navigator.didStartUserGesture();
  }

  static const _kMinFlingVelocity = 1.0; // Screen widths per second.
  static const _kDroppedSwipePageAnimationDuration = Duration(
    milliseconds: 350,
  );

  final NavigatorState navigator;
  final AnimationController controller;
  final ValueGetter<bool> getIsCurrent;
  final ValueGetter<bool> getIsActive;

  void dragUpdate(double delta) {
    controller.value -= delta;
  }

  void dragEnd(double velocity) {
    const Curve animationCurve = Curves.fastEaseInToSlowEaseOut;
    final bool isCurrent = getIsCurrent();
    final bool animateForward;

    if (!isCurrent) {
      animateForward = getIsActive();
    } else if (velocity.abs() >= _kMinFlingVelocity) {
      animateForward = velocity <= 0;
    } else {
      animateForward = controller.value > 0.5;
    }

    if (animateForward) {
      controller.animateTo(
        1.0,
        duration: _kDroppedSwipePageAnimationDuration,
        curve: animationCurve,
      );
    } else {
      if (isCurrent) {
        navigator.pop();
      }
      if (controller.isAnimating) {
        controller.animateBack(
          0.0,
          duration: _kDroppedSwipePageAnimationDuration,
          curve: animationCurve,
        );
      }
    }

    if (controller.isAnimating) {
      late AnimationStatusListener animationStatusCallback;
      animationStatusCallback = (AnimationStatus status) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(animationStatusCallback);
      };
      controller.addStatusListener(animationStatusCallback);
    } else {
      navigator.didStopUserGesture();
    }
  }
}
