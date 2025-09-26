package com.messie.messenger;

import android.os.Bundle;

import com.getcapacitor.BridgeActivity;

import com.messie.messenger.crypto.MatrixCryptoPlugin;

public class MainActivity extends BridgeActivity {
  @Override
  public void onCreate(Bundle savedInstanceState) {
    registerPlugin(MatrixCryptoPlugin.class);
    super.onCreate(savedInstanceState);
  }
}
