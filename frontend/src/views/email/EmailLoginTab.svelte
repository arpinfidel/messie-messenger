<script lang="ts">
  import { emailCredentials } from '@/viewmodels/email/EmailCredentialsStore';
  let host = '';
  let port: number = 993;
  let email = '';
  let appPassword = '';
  let isLoading = false;
  let error = '';

  async function handleSubmit() {
    isLoading = true;
    error = '';
    try {
      const creds = { host, port: Number(port), email, appPassword };
      const res = await fetch('/api/v1/email/login-test', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(creds),
      });
      if (!res.ok) {
        const text = await res.text();
        throw new Error(text || 'Request failed');
      }
      const data = await res.json();
      console.log('Fetched messages:', data.messages);
      emailCredentials.set(creds);
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
      <label class="block text-sm font-medium text-gray-700">IMAP Host</label>
      <input
        class="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-indigo-500 sm:text-sm"
        bind:value={host}
        placeholder="imap.example.com"
      />
    </div>
    <div>
      <label class="block text-sm font-medium text-gray-700">IMAP Port</label>
      <input
        type="number"
        class="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-indigo-500 sm:text-sm"
        bind:value={port}
      />
    </div>
    <div>
      <label class="block text-sm font-medium text-gray-700">Email</label>
      <input
        type="email"
        class="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-indigo-500 sm:text-sm"
        bind:value={email}
      />
    </div>
    <div>
      <label class="block text-sm font-medium text-gray-700">App Password</label>
      <input
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
    {/if}
  </form>
</div>
