import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Opens wide enough for the desktop layout, and refuses to shrink below the
  /// point where the UI stops making sense.
  ///
  /// Left alone, the window restored at roughly 400pt wide — narrower than the
  /// `medium` breakpoint, so a desktop app opened in its phone layout. The
  /// minimum keeps the side rail and the content column from being squeezed
  /// into nothing.
  private static let defaultSize = NSSize(width: 1280, height: 860)
  private static let minimumSize = NSSize(width: 720, height: 560)

  /// Set once the default has been applied, so a window the user has since
  /// resized is never resized out from under them on a later launch.
  private static let didSizeKey = "RoadmapXDidApplyDefaultWindowSize"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    self.contentMinSize = MainFlutterWindow.minimumSize

    let defaults = UserDefaults.standard
    let isFirstRun = !defaults.bool(forKey: MainFlutterWindow.didSizeKey)
    if isFirstRun {
      defaults.set(true, forKey: MainFlutterWindow.didSizeKey)
    }

    // Deferred: the nib restores its autosaved frame after awakeFromNib
    // returns, so sizing here directly is immediately overwritten.
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      // Size on a first run, and also rescue a degenerate restored frame.
      // A crash or force-quit can leave a zero-sized frame autosaved, and the
      // app then launches with a window that renders nothing at all — which
      // reads as "the app is blank" rather than as a window problem.
      if isFirstRun || self.isFrameUnusable {
        self.applyDefaultSize()
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// True when the restored frame is too small to render a usable UI.
  private var isFrameUnusable: Bool {
    let size = self.contentLayoutRect.size
    return size.width < 200 || size.height < 200
  }

  private func applyDefaultSize() {
    guard let screen = self.screen ?? NSScreen.main else { return }
    let visible = screen.visibleFrame

    var frame = self.frame
    frame.size.width = min(MainFlutterWindow.defaultSize.width, visible.width)
    frame.size.height = min(MainFlutterWindow.defaultSize.height, visible.height)
    frame.origin.x = visible.midX - frame.size.width / 2
    frame.origin.y = visible.midY - frame.size.height / 2

    self.setFrame(frame, display: true, animate: false)
  }
}
