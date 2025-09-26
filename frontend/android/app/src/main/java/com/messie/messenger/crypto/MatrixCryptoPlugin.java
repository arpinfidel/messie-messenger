package com.messie.messenger.crypto;

import android.content.Context;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.io.File;
import java.util.List;

import org.matrix.rustcomponents.sdk.crypto.DecryptedEvent;
import org.matrix.rustcomponents.sdk.crypto.DecryptionException;
import org.matrix.rustcomponents.sdk.crypto.OlmMachine;
import org.matrix.rustcomponents.sdk.crypto.ShieldState;
import uniffi.matrix_sdk_common.ShieldStateCode;

import uniffi.matrix_sdk_crypto.DecryptionSettings;
import uniffi.matrix_sdk_crypto.TrustRequirement;

@CapacitorPlugin(name = "MatrixCrypto")
public class MatrixCryptoPlugin extends Plugin {

  private static final boolean nativeLibLoaded;
  private static final String STORE_ROOT = "matrix_rust_crypto";

  private OlmMachine olmMachine;

  static {
    boolean loaded;
    try {
      System.loadLibrary("matrix_sdk_crypto_ffi");
      loaded = true;
    } catch (UnsatisfiedLinkError err) {
      loaded = false;
      System.err.println("[MatrixCryptoPlugin] Failed to load matrix_sdk_crypto_ffi: " + err.getMessage());
    }
    nativeLibLoaded = loaded;
  }

  @PluginMethod
  public void initCrypto(PluginCall call) {
    String userId = call.getString("userId");
    String deviceId = call.getString("deviceId");
    if (userId == null || deviceId == null) {
      call.reject("userId and deviceId are required");
      return;
    }

    if (!nativeLibLoaded) {
      call.reject("matrix_sdk_crypto_ffi native library not loaded");
      return;
    }

    Context context = getContext();
    if (context == null) {
      call.reject("Plugin context unavailable");
      return;
    }

    try {
      OlmMachine machine = createOlmMachine(context, userId, deviceId);
      synchronized (this) {
        if (olmMachine != null) {
          try {
            olmMachine.close();
          } catch (Exception ignored) {
            // noop
          }
        }
        olmMachine = machine;
      }
      call.resolve();
    } catch (Exception err) {
      call.reject("Failed to initialise native crypto", err);
    }
  }

  @PluginMethod
  public void decryptEvent(PluginCall call) {
    String eventJson = call.getString("eventJson");
    String roomId = call.getString("roomId");
    if (eventJson == null) {
      call.reject("eventJson is required");
      return;
    }
    if (roomId == null) {
      call.reject("roomId is required");
      return;
    }

    if (!nativeLibLoaded) {
      call.reject("matrix_sdk_crypto_ffi native library not loaded");
      return;
    }

    OlmMachine machine = getOlmMachine(call);
    if (machine == null) {
      return;
    }

    boolean handleVerificationEvents = call.getBoolean("handleVerificationEvents", false);
    boolean strictShields = call.getBoolean("strictShields", false);

    DecryptionSettings settings = new DecryptionSettings(TrustRequirement.CROSS_SIGNED_OR_LEGACY);
    try {
      DecryptedEvent decrypted = machine.decryptRoomEvent(
        eventJson,
        roomId,
        handleVerificationEvents,
        strictShields,
        settings
      );

      JSObject payload = new JSObject();
      payload.put("clearEvent", decrypted.getClearEvent());
      payload.put("senderCurve25519Key", decrypted.getSenderCurve25519Key());
      payload.put("claimedEd25519Key", decrypted.getClaimedEd25519Key());
      payload.put("forwardingCurve25519Chain", toJsArray(decrypted.getForwardingCurve25519Chain()));
      payload.put("shieldState", toShieldState(decrypted.getShieldState()));

      call.resolve(payload);
    } catch (DecryptionException err) {
      call.reject("Decryption failed", err);
    }
  }

  private JSObject toShieldState(ShieldState state) {
    JSObject obj = new JSObject();
    obj.put("color", state.getColor().name());
    ShieldStateCode code = state.getCode();
    obj.put("code", code != null ? code.name() : null);
    obj.put("message", state.getMessage());
    return obj;
  }

  private JSArray toJsArray(List<String> values) {
    JSArray arr = new JSArray();
    for (String value : values) {
      arr.put(value);
    }
    return arr;
  }

  private OlmMachine createOlmMachine(Context context, String userId, String deviceId) {
    File baseDir = new File(context.getFilesDir(), STORE_ROOT);
    if (!baseDir.exists()) {
      baseDir.mkdirs();
    }
    File userDir = new File(baseDir, sanitize(userId + "_" + deviceId));
    if (!userDir.exists()) {
      userDir.mkdirs();
    }
    return new OlmMachine(userId, deviceId, userDir.getAbsolutePath(), null);
  }

  private synchronized OlmMachine getOlmMachine(PluginCall call) {
    if (olmMachine == null) {
      call.reject("Native crypto not initialised; call initCrypto() first");
      return null;
    }
    return olmMachine;
  }

  @Override
  protected void handleOnDestroy() {
    synchronized (this) {
      if (olmMachine != null) {
        try {
          olmMachine.close();
        } catch (Exception ignored) {
          // noop
        }
        olmMachine = null;
      }
    }
    super.handleOnDestroy();
  }

  private String sanitize(String input) {
    return input.replaceAll("[^A-Za-z0-9._-]", "_");
  }
}
