<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  const dispatch = createEventDispatcher();

  let homeserverUrl: string = localStorage.getItem('matrixHomeserverUrl') || 'https://matrix.org';
  let username: string = localStorage.getItem('matrixUsername') || '';
  let password: string = '';
  let loading = false;
  let errorMsg: string | null = null;

  async function handleSubmit(event: Event) {
    event.preventDefault();
    errorMsg = null;
    loading = true;
    try {
      localStorage.setItem('matrixHomeserverUrl', homeserverUrl);
      localStorage.setItem('matrixUsername', username);
      dispatch('login', {
        homeserverUrl: homeserverUrl.trim(),
        username: username.trim(),
        password,
        onError: (msg: string) => (errorMsg = msg),
        onDone: () => (loading = false),
      });
    } catch (err: any) {
      errorMsg = err?.message || 'Login failed. Please check your details.';
      loading = false;
    }
  }
</script>

<div class="flex min-h-screen items-center justify-center bg-gray-900 p-6">
  <div class="w-full max-w-md rounded-xl border border-gray-700 bg-gray-800 p-8 text-gray-100 shadow-2xl">
    <div class="mb-6 flex flex-col items-center">
      <img src="/messie-logo.svg" alt="Messie Logo" class="mb-3 h-12 w-12" />
      <h1 class="text-center text-2xl font-semibold">Sign in to Matrix</h1>
    </div>
    {#if errorMsg}
      <div class="mb-4 rounded border border-red-800 bg-red-900/30 p-3 text-sm text-red-200">{errorMsg}</div>
    {/if}
    <form on:submit|preventDefault={handleSubmit} class="space-y-4">
      <div>
        <label class="mb-1 block text-sm font-medium text-gray-300" for="homeserver">Homeserver URL</label>
        <input
          id="homeserver"
          type="url"
          class="w-full rounded-md border border-gray-600 bg-gray-700 p-2 text-gray-100 placeholder-gray-400 focus:border-blue-500 focus:outline-none"
          placeholder="https://matrix.org"
          bind:value={homeserverUrl}
          required
        />
      </div>
      <div>
        <label class="mb-1 block text-sm font-medium text-gray-300" for="username">Username</label>
        <input
          id="username"
          type="text"
          class="w-full rounded-md border border-gray-600 bg-gray-700 p-2 text-gray-100 placeholder-gray-400 focus:border-blue-500 focus:outline-none"
          placeholder="@user:matrix.org or localpart"
          bind:value={username}
          required
        />
      </div>
      <div>
        <label class="mb-1 block text-sm font-medium text-gray-300" for="password">Password</label>
        <input
          id="password"
          type="password"
          class="w-full rounded-md border border-gray-600 bg-gray-700 p-2 text-gray-100 placeholder-gray-400 focus:border-blue-500 focus:outline-none"
          bind:value={password}
          required
        />
      </div>
      <button
        type="submit"
        class="mt-2 w-full rounded-md bg-blue-600 p-2 font-medium text-white hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-60"
        disabled={loading}
      >{loading ? 'Signing in...' : 'Sign In'}</button>
    </form>
  </div>
  </div>

<style>
  /* Component-scoped styles if needed */
</style>
