import Flutter
import UIKit
import Firebase
import AVFoundation
import Security

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "YogoshortNativeVideoPlayer") {
      registrar.register(
        YogoshortNativeVideoPlayerFactory(),
        withId: "yogoshort/native-video-player"
      )
    }
    if let controller = window?.rootViewController as? FlutterViewController {
      let deviceChannel = FlutterMethodChannel(
        name: "yogotv.com/device",
        binaryMessenger: controller.binaryMessenger
      )
      deviceChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "deviceUuid":
          let args = call.arguments as? [String: Any]
          let fallback = args?["fallback"] as? String
          result(DeviceUuidStore.deviceUuid(fallback: fallback))
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

enum DeviceUuidStore {
  private static let service = "com.yogotv.app.device"
  private static let account = "device_uuid"

  static func deviceUuid(fallback: String?) -> String {
    if let cached = read(), !cached.isEmpty {
      return cached
    }

    let value = firstNonEmpty([
      fallback,
      UIDevice.current.identifierForVendor?.uuidString.replacingOccurrences(of: "-", with: ""),
      UUID().uuidString.replacingOccurrences(of: "-", with: "")
    ])
    save(value)
    return value
  }

  private static func firstNonEmpty(_ values: [String?]) -> String {
    for value in values {
      let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !trimmed.isEmpty {
        return trimmed
      }
    }
    return UUID().uuidString.replacingOccurrences(of: "-", with: "")
  }

  private static func read() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess,
          let data = item as? Data,
          let value = String(data: data, encoding: .utf8) else {
      return nil
    }
    return value
  }

  private static func save(_ value: String) {
    let data = Data(value.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]

    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
    ]

    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecItemNotFound {
      var addQuery = query
      addQuery[kSecValueData as String] = data
      addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      SecItemAdd(addQuery as CFDictionary, nil)
    }
  }
}

final class YogoshortNativeVideoPlayerFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    return YogoshortNativeVideoPlayer(frame: frame, arguments: args)
  }
}

final class YogoshortNativeVideoPlayer: NSObject, FlutterPlatformView {
  private let container: YogoshortNativeVideoContainer
  private let player: AVPlayer
  private let layer: AVPlayerLayer
  private var endObserver: NSObjectProtocol?

  init(frame: CGRect, arguments args: Any?) {
    let params = args as? [String: Any]
    let urlString = params?["url"] as? String ?? ""
    let autoPlay = params?["autoPlay"] as? Bool ?? true
    container = YogoshortNativeVideoContainer(frame: frame)
    container.backgroundColor = .black
    player = AVPlayer()
    layer = AVPlayerLayer(player: player)
    layer.videoGravity = .resizeAspectFill
    super.init()

    container.playerLayer = layer
    container.clipsToBounds = true

    if let url = URL(string: urlString) {
      let item = AVPlayerItem(url: url)
      player.replaceCurrentItem(with: item)
      endObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: item,
        queue: .main
      ) { [weak self] _ in
        self?.player.seek(to: .zero)
        self?.player.play()
      }
      if autoPlay {
        player.play()
      } else {
        player.pause()
      }
    }
  }

  func view() -> UIView {
    return container
  }

  deinit {
    player.pause()
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
    }
  }
}

final class YogoshortNativeVideoContainer: UIView {
  var playerLayer: AVPlayerLayer? {
    didSet {
      oldValue?.removeFromSuperlayer()
      if let playerLayer {
        layer.addSublayer(playerLayer)
        setNeedsLayout()
      }
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    playerLayer?.frame = bounds
  }
}
