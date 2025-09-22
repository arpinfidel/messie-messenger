<script lang="ts">
  import { onDestroy } from 'svelte';
  import { EmailViewModel } from '@/viewmodels/email/EmailViewModel';

  const emailViewModel = EmailViewModel.getInstance();
  const credentialsStore = emailViewModel.getCredentials();
  const loginStatusStore = emailViewModel.getLoginStatus();
  const loginErrorStore = emailViewModel.getLoginError();
  const mailboxStatusStore = emailViewModel.getMailboxStatus();
  const mailboxErrorStore = emailViewModel.getMailboxError();

  let host = '';
  let port: number = 993;
  let email = '';
  let appPassword = '';

  const unsubscribeCredentials = credentialsStore.subscribe((creds) => {
    if (!creds) {
      host = '';
      port = 993;
      email = '';
      appPassword = '';
      return;
    }

    host = creds.host ?? '';
    port = creds.port ?? 993;
    email = creds.email ?? '';
    appPassword = '';
  });

  onDestroy(() => {
    unsubscribeCredentials();
  });

  $: isAuthenticating = $loginStatusStore === 'authenticating';
  $: loginSuccessful = $loginStatusStore === 'authenticated' && !$loginErrorStore;
  $: combinedError = $loginErrorStore || $mailboxErrorStore;
  $: hasCredentials = Boolean($credentialsStore);
  $: isMailboxRefreshing = $mailboxStatusStore === 'refreshing';

  async function handleSubmit() {
    try {
      await emailViewModel.login({ host, port: Number(port), email, appPassword });
    } catch (error) {
      console.error('Email login failed', error);
    }
  }

  async function handleRefresh() {
    try {
      await emailViewModel.refreshMailbox();
    } catch (error) {
      console.error('Failed to refresh mailbox', error);
    }
  }

  function handleLogout() {
    emailViewModel.logout();
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
    <div class="flex flex-wrap items-center gap-2">
      <button
        type="submit"
        class="rounded-md bg-indigo-600 px-4 py-2 text-white shadow-sm hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-60"
        disabled={isAuthenticating}
      >
        {#if isAuthenticating}
          Connecting…
        {:else if loginSuccessful}
          Reconnect
        {:else}
          Connect
        {/if}
      </button>

      {#if hasCredentials}
        <button
          type="button"
          class="rounded-md border border-indigo-600 px-4 py-2 text-indigo-600 shadow-sm hover:bg-indigo-50 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-60"
          on:click={handleRefresh}
          disabled={isMailboxRefreshing}
        >
          {#if isMailboxRefreshing}
            Refreshing…
          {:else}
            Refresh mailboxes
          {/if}
        </button>

        <button
          type="button"
          class="rounded-md border border-gray-300 px-4 py-2 text-gray-700 shadow-sm hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-gray-400 focus:ring-offset-2"
          on:click={handleLogout}
        >
          Log out
        </button>
      {/if}
    </div>

    {#if combinedError}
      <div class="text-sm text-red-600">{combinedError}</div>
    {:else if loginSuccessful}
      <div class="text-sm text-green-600">Connected successfully.</div>
    {/if}

    {#if $mailboxStatusStore === 'refreshing'}
      <div class="text-sm text-gray-500">Refreshing mailbox data…</div>
    {:else if $mailboxStatusStore === 'ready' && loginSuccessful}
      <div class="text-sm text-gray-500">Mailboxes are up to date.</div>
    {/if}
  </form>
</div>
