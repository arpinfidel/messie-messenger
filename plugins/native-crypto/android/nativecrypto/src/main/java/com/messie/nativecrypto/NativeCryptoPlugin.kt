package com.messie.nativecrypto

import com.getcapacitor.JSObject
import com.getcapacitor.Logger
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.annotation.PluginMethod

@CapacitorPlugin(name = "NativeCrypto")
class NativeCryptoPlugin : Plugin() {
    private var libLoaded: Boolean = false

    override fun load() {
        super.load()
        libLoaded = try {
            System.loadLibrary("messie_crypto_ffi")
            true
        } catch (error: UnsatisfiedLinkError) {
            Logger.warn("NativeCrypto", "messie_crypto_ffi library not present: ${error.message}")
            false
        }
    }

    @PluginMethod
    fun init(call: PluginCall) {
        if (!libLoaded) {
            call.reject("messie_crypto_ffi native library not loaded")
            return
        }
        call.reject("Native crypto init not implemented yet")
    }

    @PluginMethod
    fun encryptEvent(call: PluginCall) {
        call.reject("Native crypto encryptEvent not implemented yet")
    }

    @PluginMethod
    fun decryptEvent(call: PluginCall) {
        call.reject("Native crypto decryptEvent not implemented yet")
    }

    @PluginMethod
    fun downloadKeys(call: PluginCall) {
        call.reject("Native crypto downloadKeys not implemented yet")
    }

    @PluginMethod
    fun refreshDeviceLists(call: PluginCall) {
        call.reject("Native crypto refreshDeviceLists not implemented yet")
    }

    @PluginMethod
    fun getUserVerificationStatus(call: PluginCall) {
        call.reject("Native crypto getUserVerificationStatus not implemented yet")
    }

    @PluginMethod
    fun setDeviceVerified(call: PluginCall) {
        call.reject("Native crypto setDeviceVerified not implemented yet")
    }

    @PluginMethod
    fun flush(call: PluginCall) {
        call.reject("Native crypto flush not implemented yet")
    }

    @PluginMethod
    fun close(call: PluginCall) {
        call.reject("Native crypto close not implemented yet")
    }
}
