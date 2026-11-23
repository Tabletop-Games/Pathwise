import Darwin
import Flutter
import Network
import StoreKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let network = NWPathMonitor()
  private let processBoot = Int.random(in: 0..<Int.max)

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    network.start(queue: DispatchQueue(label: "games.tabletop.pathwise.network"))
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let sharing = FlutterMethodChannel(
      name: "games.tabletop.pathwise/share",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    sharing.setMethodCallHandler { call, result in
      guard let arguments = call.arguments as? [String: String],
        let text = arguments["content"]
      else {
        result(false)
        return
      }
      switch call.method {
      case "web":
        guard let url = URL(string: text), url.scheme == "https" else {
          result(false)
          return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: { result($0) })
      case "whatsapp":
        var link = URLComponents(string: "https://wa.me/")!
        link.queryItems = [URLQueryItem(name: "text", value: text)]
        UIApplication.shared.open(link.url!, options: [.universalLinksOnly: true],
                                  completionHandler: { result($0) })
      case "chooser":
        let root = UIApplication.shared.connectedScenes
          .compactMap { $0 as? UIWindowScene }
          .first { $0.activationState == .foregroundActive }?
          .windows.first { $0.isKeyWindow }?.rootViewController
        guard var presenter = root else {
          result(false)
          return
        }
        while let next = presenter.presentedViewController { presenter = next }
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = presenter.view
        activity.popoverPresentationController?.sourceRect = CGRect(
          x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        presenter.present(activity, animated: true)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let commerce = FlutterMethodChannel(
      name: "games.tabletop.pathwise/commerce",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    commerce.setMethodCallHandler { call, result in
      guard call.method == "verifyStoreKitPurchase" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: String],
        let identifier = arguments["transaction"].flatMap(UInt64.init),
        let product = arguments["product"]
      else {
        result(false)
        return
      }
      Task { @MainActor in
        for await entry in StoreKit.Transaction.unfinished {
          if case .verified(let transaction) = entry,
            transaction.id == identifier,
            transaction.productID == product,
            transaction.revocationDate == nil {
            result(true)
            return
          }
        }
        for await entry in StoreKit.Transaction.currentEntitlements {
          if case .verified(let transaction) = entry,
            transaction.id == identifier,
            transaction.productID == product,
            transaction.revocationDate == nil {
            result(true)
            return
          }
        }
        result(false)
      }
    }
    let clock = FlutterMethodChannel(
      name: "games.tabletop.pathwise/clock",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    clock.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "bootTime":
        var boot = timeval()
        var length = MemoryLayout<timeval>.size
        let available = sysctlbyname("kern.boottime", &boot, &length, nil, 0) == 0
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let milliseconds = Double(mach_continuous_time()) * Double(timebase.numer)
          / Double(timebase.denom) / 1_000_000
        result([available ? Int(boot.tv_sec) : self.processBoot, Int(milliseconds)])
      case "online":
        result(self.network.currentPath.status == .satisfied)
      case "adsConfigured":
        let id = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String
        result(id?.range(of: #"^ca-app-pub-[0-9]{16}~[0-9]{10}$"#,
          options: .regularExpression) != nil &&
          id?.hasPrefix("ca-app-pub-3940256099942544~") == false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
