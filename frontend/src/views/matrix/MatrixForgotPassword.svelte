<script lang="ts">
  import { onMount } from 'svelte';
  import { createEventDispatcher } from 'svelte';
  import { MatrixViewModel } from '@/viewmodels/matrix/MatrixViewModel';

  const dispatch = createEventDispatcher();
  let homeserverUrl: string =
    new URLSearchParams(window.location.search).get('hs') ||
    localStorage.getItem('matrixHomeserverUrl') ||
    'https://matrix.org';
  let email = '';
  let newPassword = '';
  let loading = false;
  let message: string | null = null;
  let errorMsg: string | null = null;
  let phase: 'request' | 'reset' | 'sent' | 'completed' = 'request';

  let sid: string | null = null;
  let clientSecret: string | null = null;

  onMount(() => {
    const params = new URLSearchParams(window.location.search);
    sid = params.get('sid');
    // Prefer stored secret (set when we requested the token)
    if (sid) {
      try {
        clientSecret =
          localStorage.getItem(`matrix:pwdreset:${sid}:client_secret`) ||
          params.get('client_secret');
      } catch {
        clientSecret = params.get('client_secret');
      }
      phase = 'reset';
      if (!clientSecret) {
        errorMsg =
          'Could not find your reset session. Please start the reset again from this browser.';
      }
    } else {
      clientSecret = params.get('client_secret');
    }
  });

  async function requestReset(event: Event) {
    event.preventDefault();
    loading = true;
    errorMsg = null;
    try {
      const vm = MatrixViewModel.getInstance();
      const nextLink = `${window.location.origin}${window.location.pathname}?hs=${encodeURIComponent(
        homeserverUrl,
      )}`;
      const { sid: newSid, clientSecret: newSecret } = await vm.requestPasswordReset(
        homeserverUrl.trim(),
        email.trim(),
        nextLink,
      );
      // Keep in localStorage keyed by sid for redirect completion
      try {
        localStorage.setItem(`matrix:pwdreset:${newSid}:client_secret`, newSecret);
        localStorage.setItem('matrixHomeserverUrl', homeserverUrl.trim());
      } catch {}
      phase = 'sent';
      message = 'Confirmation email sent. Check your inbox and click the link to continue. Keep this tab open; you will return here automatically.';
    } catch (err: any) {
      errorMsg = err?.message || 'Failed to send reset email.';
    } finally {
      loading = false;
    }
  }

  async function resetPassword(event: Event) {
    event.preventDefault();
    if (!sid || !clientSecret) {
      errorMsg = 'Missing reset session. Please restart the reset flow.';
      return;
    }
    loading = true;
    errorMsg = null;
    try {
      const vm = MatrixViewModel.getInstance();
      await vm.resetPassword(homeserverUrl.trim(), clientSecret, sid, newPassword);
      phase = 'completed';
      message = 'Password updated. You can now sign in.';
      // Clear query params
      window.history.replaceState({}, '', window.location.pathname);
      try {
        localStorage.removeItem(`matrix:pwdreset:${sid}:client_secret`);
      } catch {}
    } catch (err: any) {
      errorMsg = err?.message || 'Failed to reset password.';
    } finally {
      loading = false;
    }
  }
</script>

<div class="flex min-h-screen items-center justify-center bg-gray-900 p-6">
  <div class="w-full max-w-md rounded-xl border border-gray-700 bg-gray-800 p-8 text-gray-100 shadow-2xl">
    {#if phase === 'request'}
      <h1 class="mb-4 text-center text-2xl font-semibold">Reset Password</h1>
      {#if errorMsg}
        <div class="mb-4 rounded border border-red-800 bg-red-900/30 p-3 text-sm text-red-200">{errorMsg}</div>
      {/if}
      <form on:submit|preventDefault={requestReset} class="space-y-4">
        <div>
          <label class="mb-1 block text-sm font-medium text-gray-300" for="homeserver">Homeserver URL</label>
          <input
            id="homeserver"
            type="url"
            class="w-full rounded-md border border-gray-600 bg-gray-700 p-2 text-gray-100 placeholder-gray-400 focus:border-blue-500 focus:outline-none"
            bind:value={homeserverUrl}
            required
          />
        </div>
        <div>
          <label class="mb-1 block text-sm font-medium text-gray-300" for="email">Email</label>
          <input
            id="email"
            type="email"
            class="w-full rounded-md border border-gray-600 bg-gray-700 p-2 text-gray-100 placeholder-gray-400 focus:border-blue-500 focus:outline-none"
            bind:value={email}
            required
          />
        </div>
        <button
          type="submit"
          class="mt-2 w-full rounded-md bg-blue-600 p-2 font-medium text-white hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-60"
          disabled={loading}
        >{loading ? 'Sending...' : 'Send Reset Email'}</button>
      </form>
      <button class="mt-4 w-full text-sm text-blue-400 hover:underline" on:click={() => dispatch('cancel')}>Back to login</button>
    {:else if phase === 'reset'}
      <h1 class="mb-4 text-center text-2xl font-semibold">Set New Password</h1>
      {#if errorMsg}
        <div class="mb-4 rounded border border-red-800 bg-red-900/30 p-3 text-sm text-red-200">{errorMsg}</div>
      {/if}
      <form on:submit|preventDefault={resetPassword} class="space-y-4">
        <div>
          <label class="mb-1 block text-sm font-medium text-gray-300" for="newpass">New Password</label>
          <input
            id="newpass"
            type="password"
            class="w-full rounded-md border border-gray-600 bg-gray-700 p-2 text-gray-100 placeholder-gray-400 focus:border-blue-500 focus:outline-none"
            bind:value={newPassword}
            required
          />
        </div>
        <button
          type="submit"
          class="mt-2 w-full rounded-md bg-blue-600 p-2 font-medium text-white hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-60"
          disabled={loading}
        >{loading ? 'Updating...' : 'Update Password'}</button>
      </form>
    {:else if phase === 'sent'}
      <h1 class="mb-4 text-center text-2xl font-semibold">Check Your Email</h1>
      {#if message}
        <p class="mb-4 text-center">{message}</p>
      {/if}
      <p class="text-center text-sm text-gray-400">After you confirm via the email, you’ll be redirected back here to set a new password.</p>
    {:else if phase === 'completed'}
      {#if message}
        <p class="mb-4 text-center">{message}</p>
      {/if}
      <button
        class="mt-2 w-full rounded-md bg-blue-600 p-2 font-medium text-white hover:bg-blue-500"
        on:click={() => dispatch('done')}
      >Back to login</button>
    {/if}
  </div>
</div>

<style>
  /* Component scoped styles */
</style>
