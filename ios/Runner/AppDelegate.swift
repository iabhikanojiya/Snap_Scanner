import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var pdfChannel: FlutterMethodChannel?
  /// PDF opened before Flutter was listening; handed over on request.
  private var pendingPdfPath: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "snap_scanner/incoming_pdf",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        if call.method == "getInitialPdf" {
          result(self?.pendingPdfPath)
          self?.pendingPdfPath = nil
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      pdfChannel = channel
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// "Open in Snap Scanner" from Files, Mail, etc.
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard url.isFileURL, url.pathExtension.lowercased() == "pdf",
          let path = copyToCache(url) else {
      return super.application(app, open: url, options: options)
    }
    pendingPdfPath = path
    // If Flutter is already listening, deliver now; otherwise it will ask
    // for the pending path once ready.
    pdfChannel?.invokeMethod("onPdf", arguments: path) { [weak self] result in
      if (result as? NSObject) != FlutterMethodNotImplemented, !(result is FlutterError) {
        self?.pendingPdfPath = nil
      }
    }
    return true
  }

  private func copyToCache(_ url: URL) -> String? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("incoming/\(Int(Date().timeIntervalSince1970 * 1000))")
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let target = dir.appendingPathComponent(url.lastPathComponent)
      try FileManager.default.copyItem(at: url, to: target)
      return target.path
    } catch {
      return nil
    }
  }
}
