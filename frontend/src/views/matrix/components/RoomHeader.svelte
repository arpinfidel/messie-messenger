<script lang="ts">
  import { MatrixViewModel } from '../../../viewmodels/matrix';

  export let title: string = 'Matrix Room';
  export let messageCount: number = 0;
  export let className: string = '';
  export let roomId: string = '';

  const matrixViewModel = MatrixViewModel.getInstance();
  let showInfo = false;
  let members: any[] = [];
  let cryptoDebug: any = null;
  let recoveryKeyInput: string = '';
  let verifyBusy = false;
  let verifyResult: any = null;
  let bootstrapBusy = false;
  let bootstrapResult: any = null;
  let importJsonText = '';
  let importBusy = false;
  let importResult: any = null;
  let statusBusy = false;
  let statusResult: any = null;
  let pubBusy = false;
  let pubResult: any = null;

  async function openInfo() {
    if (!roomId) return;
    try {
      members = await matrixViewModel.getRoomMembers(roomId);
    } catch (e) {
      console.error('[RoomHeader] failed to load members', e);
      members = [];
    }
    try {
      // @ts-ignore lite client supports it; sdk path may ignore
      const anyClient: any = (matrixViewModel as any);
      if (typeof anyClient?.client?.getCryptoDebugInfo === 'function') {
        cryptoDebug = await anyClient.client.getCryptoDebugInfo(roomId);
      } else if (typeof anyClient?.getCryptoDebugInfo === 'function') {
        cryptoDebug = await anyClient.getCryptoDebugInfo(roomId);
      } else if (typeof (MatrixViewModel as any)?.getInstance()?.client?.getCryptoDebugInfo === 'function') {
        cryptoDebug = await (MatrixViewModel as any).getInstance().client.getCryptoDebugInfo(roomId);
      } else if (typeof (MatrixViewModel as any)?.getInstance()?.getCryptoDebugInfo === 'function') {
        cryptoDebug = await (MatrixViewModel as any).getInstance().getCryptoDebugInfo(roomId);
      }
    } catch (e) {
      cryptoDebug = null;
    }
    showInfo = true;
  }

  function closeInfo() {
    showInfo = false;
  }

  async function verifyViaRecoveryKey() {
    verifyBusy = true;
    verifyResult = null;
    try {
      const vmAny: any = MatrixViewModel.getInstance?.() ?? matrixViewModel;
      const client: any = vmAny?.client ?? vmAny;
      if (typeof client?.verifyWithRecoveryKey !== 'function') {
        verifyResult = { error: 'verifyWithRecoveryKey not available' };
        return;
      }
      const res = await client.verifyWithRecoveryKey(recoveryKeyInput.trim());
      verifyResult = res || { error: 'No result' };
      // Refresh crypto debug snapshot after verification
      try {
        if (roomId && typeof client?.getCryptoDebugInfo === 'function') {
          cryptoDebug = await client.getCryptoDebugInfo(roomId);
        }
      } catch {}
    } catch (e) {
      verifyResult = { error: String(e) };
    } finally {
      verifyBusy = false;
    }
  }

  async function bootstrapCrossSigning() {
    bootstrapBusy = true;
    bootstrapResult = null;
    try {
      const vmAny: any = MatrixViewModel.getInstance?.() ?? matrixViewModel;
      const client: any = vmAny?.client ?? vmAny;
      if (typeof client?.bootstrapCrossSigning !== 'function') {
        bootstrapResult = { error: 'bootstrapCrossSigning not available' };
        return;
      }
      const ok = await client.bootstrapCrossSigning(false);
      bootstrapResult = { ok };
      // refresh crypto debug
      try {
        if (roomId && typeof client?.getCryptoDebugInfo === 'function') {
          cryptoDebug = await client.getCryptoDebugInfo(roomId);
        }
      } catch {}
    } catch (e) {
      bootstrapResult = { error: String(e) };
    } finally {
      bootstrapBusy = false;
    }
  }

  async function importSecretsBundle() {
    importBusy = true;
    importResult = null;
    try {
      let parsed: any = null;
      try { parsed = JSON.parse(importJsonText); } catch (e) {
        importResult = { error: 'Invalid JSON' };
        return;
      }
      const vmAny: any = MatrixViewModel.getInstance?.() ?? matrixViewModel;
      const client: any = vmAny?.client ?? vmAny;
      if (typeof client?.importSecretsBundleJson !== 'function') {
        importResult = { error: 'importSecretsBundleJson not available' };
        return;
      }
      const ok = await client.importSecretsBundleJson(parsed);
      importResult = { ok };
      try {
        if (roomId && typeof client?.getCryptoDebugInfo === 'function') {
          cryptoDebug = await client.getCryptoDebugInfo(roomId);
        }
      } catch {}
    } catch (e) {
      importResult = { error: String(e) };
    } finally {
      importBusy = false;
    }
  }

  async function checkCrossSigningStatus() {
    statusBusy = true;
    statusResult = null;
    try {
      const vmAny: any = MatrixViewModel.getInstance?.() ?? matrixViewModel;
      const client: any = vmAny?.client ?? vmAny;
      if (typeof client?.checkCrossSigningStatus !== 'function') {
        statusResult = { error: 'checkCrossSigningStatus not available' };
        return;
      }
      statusResult = await client.checkCrossSigningStatus();
    } catch (e) {
      statusResult = { error: String(e) };
    } finally {
      statusBusy = false;
    }
  }

  async function publishSelfSignature() {
    pubBusy = true;
    pubResult = null;
    try {
      const vmAny: any = MatrixViewModel.getInstance?.() ?? matrixViewModel;
      const client: any = vmAny?.client ?? vmAny;
      if (typeof client?.publishSelfSignature !== 'function') {
        pubResult = { error: 'publishSelfSignature not available' };
        return;
      }
      pubResult = await client.publishSelfSignature();
    } catch (e) {
      pubResult = { error: String(e) };
    } finally {
      pubBusy = false;
    }
  }
</script>

<div class="room-header {className}">
  <div class="flex items-center space-x-3">
    <div class="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-emerald-500 to-teal-600 shadow-lg">
      <svg class="h-5 w-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
      </svg>
    </div>
    <div>
      <h2 class="text-lg font-semibold text-gray-900 dark:text-white">{title}</h2>
      <p class="text-sm text-gray-500 dark:text-gray-400">{messageCount} messages</p>
    </div>
  </div>
  <div class="flex items-center space-x-2">
    <button
      class="rounded-lg p-2 text-gray-500 transition-colors hover:bg-gray-100 hover:text-gray-700 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-gray-300"
      on:click={openInfo}
    >
      <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
    </button>
  </div>
</div>

{#if showInfo}
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50">
    <div class="max-h-[80vh] w-full max-w-lg overflow-auto rounded-lg bg-white p-4 shadow-lg dark:bg-gray-800">
      <h3 class="mb-2 text-lg font-semibold">Debug Info</h3>
      <p class="mb-2 text-sm">Room ID: {roomId}</p>
      <div class="mb-3 rounded border p-2 text-xs">
        <div class="font-semibold mb-1">Crypto</div>
        {#if cryptoDebug}
          <div>Encrypted: {cryptoDebug?.encryptionState ? 'yes' : 'no'}</div>
          {#if cryptoDebug?.roomSettings}
            <div>Algorithm: {cryptoDebug.roomSettings.algorithm}</div>
            <div>onlyAllowTrustedDevices: {String(cryptoDebug.roomSettings.onlyAllowTrustedDevices)}</div>
            <div>Rotation(ms): {cryptoDebug.roomSettings.sessionRotationPeriodMs ?? 'n/a'}</div>
            <div>Rotation(msgs): {cryptoDebug.roomSettings.sessionRotationPeriodMessages ?? 'n/a'}</div>
          {/if}
          {#if cryptoDebug?.lastShare}
            <div class="mt-2">Last Share → {new Date(cryptoDebug.lastShare.ts).toLocaleTimeString()}</div>
            <div>eventType: {cryptoDebug.lastShare.eventType}</div>
            <div>targets: users={cryptoDebug.lastShare.userCount}, devices={cryptoDebug.lastShare.deviceCount}</div>
            <div>sampleUsers: {cryptoDebug.lastShare.sampleUsers?.join(', ')}</div>
            <div>rotated: {String(cryptoDebug.lastShare.rotated || false)}</div>
          {/if}
        {:else}
          <div class="text-gray-500">No crypto info available</div>
        {/if}
      </div>

      <div class="mb-3 rounded border p-2 text-xs">
        <div class="font-semibold mb-1">Verify via Recovery Key</div>
        <div class="flex items-center space-x-2">
          <input
            type="text"
            placeholder="Enter recovery key (Base58)"
            class="flex-1 rounded border px-2 py-1 text-xs dark:bg-gray-900"
            bind:value={recoveryKeyInput}
          />
          <button
            class="rounded bg-emerald-600 px-3 py-1 text-white disabled:opacity-50"
            disabled={verifyBusy || !recoveryKeyInput.trim()}
            on:click={verifyViaRecoveryKey}
          >
            {verifyBusy ? 'Verifying…' : 'Verify'}
          </button>
        </div>
        {#if verifyResult}
          <pre class="mt-2 max-h-40 overflow-auto rounded bg-gray-100 p-2 text-[11px] dark:bg-gray-900">{JSON.stringify(verifyResult, null, 2)}</pre>
        {/if}
      </div>

      <div class="mb-3 rounded border p-2 text-xs">
        <div class="font-semibold mb-1">Check Cross‑Signing Status</div>
        <button
          class="rounded bg-slate-600 px-3 py-1 text-white disabled:opacity-50"
          disabled={statusBusy}
          on:click={checkCrossSigningStatus}
        >
          {statusBusy ? 'Checking…' : 'Check Status'}
        </button>
        {#if statusResult}
          <pre class="mt-2 max-h-40 overflow-auto rounded bg-gray-100 p-2 text-[11px] dark:bg-gray-900">{JSON.stringify(statusResult, null, 2)}</pre>
        {/if}
      </div>

      <div class="mb-3 rounded border p-2 text-xs">
        <div class="font-semibold mb-1">Publish Self‑Signature</div>
        <button
          class="rounded bg-amber-600 px-3 py-1 text-white disabled:opacity-50"
          disabled={pubBusy}
          on:click={publishSelfSignature}
        >
          {pubBusy ? 'Publishing…' : 'Publish'}
        </button>
        {#if pubResult}
          <pre class="mt-2 max-h-40 overflow-auto rounded bg-gray-100 p-2 text-[11px] dark:bg-gray-900">{JSON.stringify(pubResult, null, 2)}</pre>
        {/if}
      </div>

      <div class="mb-3 rounded border p-2 text-xs">
        <div class="font-semibold mb-1">Bootstrap Cross‑Signing</div>
        <div class="flex items-center space-x-2">
          <button
            class="rounded bg-indigo-600 px-3 py-1 text-white disabled:opacity-50"
            disabled={bootstrapBusy}
            on:click={bootstrapCrossSigning}
          >
            {bootstrapBusy ? 'Bootstrapping…' : 'Bootstrap'}
          </button>
        </div>
        {#if bootstrapResult}
          <pre class="mt-2 max-h-40 overflow-auto rounded bg-gray-100 p-2 text-[11px] dark:bg-gray-900">{JSON.stringify(bootstrapResult, null, 2)}</pre>
        {/if}
      </div>

      <div class="mb-3 rounded border p-2 text-xs">
        <div class="font-semibold mb-1">Import Secrets Bundle (JSON)</div>
        <textarea
          class="w-full rounded border p-2 text-[11px] dark:bg-gray-900"
          rows="4"
          placeholder="Paste SecretsBundle JSON exported from a verified device"
          bind:value={importJsonText}
        />
        <div class="mt-2">
          <button
            class="rounded bg-purple-600 px-3 py-1 text-white disabled:opacity-50"
            disabled={importBusy || !importJsonText.trim()}
            on:click={importSecretsBundle}
          >
            {importBusy ? 'Importing…' : 'Import'}
          </button>
        </div>
        {#if importResult}
          <pre class="mt-2 max-h-40 overflow-auto rounded bg-gray-100 p-2 text-[11px] dark:bg-gray-900">{JSON.stringify(importResult, null, 2)}</pre>
        {/if}
      </div>
      <pre class="max-h-[60vh] overflow-auto rounded bg-gray-100 p-2 text-xs dark:bg-gray-900">{JSON.stringify(members, null, 2)}</pre>
      <button
        class="mt-4 rounded bg-blue-500 px-4 py-2 text-white hover:bg-blue-600"
        on:click={closeInfo}
      >
        Close
      </button>
    </div>
  </div>
{/if}

<style>
  .room-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1rem 1.5rem;
    background: var(--color-panel);
    border-bottom: 1px solid var(--color-panel-border);
    position: sticky;
    top: 0;
    z-index: 10;
  }
</style>
