import 'dart:async';
import 'package:screen_state/screen_state.dart';

class ScreenMonitor {
  late Screen _screen;
  StreamSubscription<ScreenStateEvent>? _screenSub;

  void start(void Function(bool screenOn) onChange) {
    _screen = Screen();
    _screenSub = _screen.screenStateStream.listen((event) {
      onChange(event == ScreenStateEvent.SCREEN_ON || event == ScreenStateEvent.SCREEN_UNLOCKED);
    });
  }

  void stop() {
    _screenSub?.cancel();
    _screenSub = null;
  }
}
