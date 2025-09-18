<script lang="ts">
  import { EmailViewModel } from '@/viewmodels/email/EmailViewModel';

  const emailViewModel = EmailViewModel.getInstance();
  let host = '';
  let port: number = 993;
  let email = '';
  let appPassword = '';
  let isLoading = false;
  let error = '';
  let successMessage = '';

  async function handleSubmit() {
    isLoading = true;
    error = '';
    successMessage = '';
    try {
      await emailViewModel.testAndStoreCredentials({ host, port: Number(port), email, appPassword });
      successMessage = 'Connected successfully.';
    } catch (e: any) {
      error = e?.message ?? 'Unknown error occurred';
    } finally {
      isLoading = false;
    }
  }
</script>

<div class="p-4">
  <h1 class="mb-4 text-2xl font-bold">Email Login Test</h1>
  <form on:submit|preventDefault={handleSubmit} class="space-y-4">
    <div>
      <label class="block text-sm font-medium text-gray-700" for="email-imap-host">IMAP Host</label>
      <input id="email-imap-host"
        class="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-indigo-500 sm:text-sm"
        bind:value={host}
        placeholder="imap.example.com"
      />
    </div>
    <div>
      <label class="block text-sm font-medium text-gray-700" for="email-imap-port">IMAP Port</label>
      <input id="email-imap-port"
        type="number"
        class="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-indigo-500 sm:text-sm"
        bind:value={port}
      />
    </div>
    <div>
      <label class="block text-sm font-medium text-gray-700" for="email-address">Email</label>
      <input id="email-address"
        type="email"
        class="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-indigo-500 sm:text-sm"
        bind:value={email}
      />
    </div>
    <div>
      <label class="block text-sm font-medium text-gray-700" for="email-app-password">App Password</label>
      <input id="email-app-password"
        type="password"
        class="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-indigo-500 sm:text-sm"
        bind:value={appPassword}
      />
    </div>
    <button
      type="submit"
      class="rounded-md bg-indigo-600 px-4 py-2 text-white shadow-sm hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
      disabled={isLoading}
    >
      {#if isLoading}Loading...{:else}Login & Fetch{/if}
    </button>
    {#if error}
      <div class="text-red-500">{error}</div>
    {:else if successMessage}
      <div class="text-green-500">{successMessage}</div>
    {/if}
  </form>
</div>
