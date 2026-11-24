import 'package:PiliPlus/common/widgets/gesture/trackpad_back_gesture.dart';
import 'package:flutter/gestures.dart'
    show
        ScaleGestureRecognizer,
        RecognizerCallback,
        GestureRecognizer,
        DeviceGestureSettings,
        PointerDownEvent,
        PointerPanZoomStartEvent;

mixin PlayerGestureMixin on GestureRecognizer {
  bool isPosAllowed = true;

  @override
  T? invokeCallback<T>(
    String name,
    RecognizerCallback<T> callback, {
    String Function()? debugReport,
  }) {
    if (!isPosAllowed) return null;
    return super.invokeCallback(name, callback, debugReport: debugReport);
  }
}

class PlayerScaleGestureRecognizer extends ScaleGestureRecognizer
    with PlayerGestureMixin {
  PlayerScaleGestureRecognizer({
    super.debugOwner,
    super.supportedDevices,
    super.allowedButtonsFilter,
    super.dragStartBehavior,
    super.trackpadScrollCausesScale,
    super.trackpadScrollToScaleFactor,
  });

  bool _isTrackpad = false;

  /// An infinite pan slop: only accept on scale changes.
  static const _scaleOnlySettings = DeviceGestureSettings(
    touchSlop: double.infinity,
  );

  /// Panning the video is disabled and trackpad pans are handled by the
  /// player with a raw [Listener], so a trackpad pan without pinching does
  /// nothing here. Don't claim it, leave it to e.g. [TrackpadBackGesture].
  @override
  DeviceGestureSettings? get gestureSettings =>
      _isTrackpad && TrackpadBackGesture.enabled
      ? _scaleOnlySettings
      : super.gestureSettings;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _isTrackpad = false;
    super.addAllowedPointer(event);
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    _isTrackpad = true;
    super.addAllowedPointerPanZoom(event);
  }
}
