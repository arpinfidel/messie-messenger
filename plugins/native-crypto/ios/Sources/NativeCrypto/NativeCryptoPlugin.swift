import Capacitor
import Foundation

@objc(NativeCryptoPlugin)
public class NativeCryptoPlugin: CAPPlugin {
    private var libraryLoaded = false

    public override func load() {
        super.load()
        libraryLoaded = NativeCryptoLoader.load()
    }

    @objc(init:)
    public func initPlugin(_ call: CAPPluginCall) {
        guard libraryLoaded else {
            call.reject("messie_crypto_ffi native library not loaded")
            return
        }
        call.reject("Native crypto init not implemented yet")
    }

    @objc public func encryptEvent(_ call: CAPPluginCall) {
        call.reject("Native crypto encryptEvent not implemented yet")
    }

    @objc public func decryptEvent(_ call: CAPPluginCall) {
        call.reject("Native crypto decryptEvent not implemented yet")
    }

    @objc public func downloadKeys(_ call: CAPPluginCall) {
        call.reject("Native crypto downloadKeys not implemented yet")
    }

    @objc public func refreshDeviceLists(_ call: CAPPluginCall) {
        call.reject("Native crypto refreshDeviceLists not implemented yet")
    }

    @objc public func getUserVerificationStatus(_ call: CAPPluginCall) {
        call.reject("Native crypto getUserVerificationStatus not implemented yet")
    }

    @objc public func setDeviceVerified(_ call: CAPPluginCall) {
        call.reject("Native crypto setDeviceVerified not implemented yet")
    }

    @objc public func flush(_ call: CAPPluginCall) {
        call.reject("Native crypto flush not implemented yet")
    }

    @objc public func close(_ call: CAPPluginCall) {
        call.reject("Native crypto close not implemented yet")
    }
}

private enum NativeCryptoLoader {
    static func load() -> Bool {
        if libraryLoaded {
            return true
        }
        // Loading the XCFramework happens automatically via linker when bundled.
        libraryLoaded = NSClassFromString("NativeCryptoFFI") != nil
        return libraryLoaded
    }

    private static var libraryLoaded = false
}
