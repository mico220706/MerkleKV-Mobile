import Flutter
import UIKit

public class MerkleKvMobilePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "merkle_kv_mobile", binaryMessenger: registrar.messenger())
    let instance = MerkleKvMobilePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    // TODO: Implement platform-specific methods
    result(FlutterMethodNotImplemented)
  }
}
