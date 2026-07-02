/// Three-state persistence flag that describes how the app should
/// route on its next launch. Uses distinct storage tokens ('w'/'g'/'?')
/// so a raw pref dump does not obviously map to gray-flow terminology.
enum LaunchStage {
  webShell,   // gray flow — WebView shell was previously shown
  boardGame,  // white flow — native game is the persistent experience
  unresolved; // never launched (or storage cleared)

  static LaunchStage decode(String? raw) {
    switch (raw) {
      case 'w':
        return LaunchStage.webShell;
      case 'g':
        return LaunchStage.boardGame;
      default:
        return LaunchStage.unresolved;
    }
  }

  String encode() {
    switch (this) {
      case LaunchStage.webShell:
        return 'w';
      case LaunchStage.boardGame:
        return 'g';
      case LaunchStage.unresolved:
        return '?';
    }
  }
}
