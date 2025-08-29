<script lang="ts">
  import { CloudAuthViewModel } from '../../viewmodels/cloud-auth/CloudAuthViewModel';
  import { MatrixViewModel } from '../../viewmodels/matrix/MatrixViewModel';
  import { onMount } from 'svelte';

  let matrixVm: MatrixViewModel;
  let todoVm: CloudAuthViewModel;
  let isLoading = false;
  let errorMessage = '';

  onMount(() => {
    matrixVm = MatrixViewModel.getInstance();
    todoVm = CloudAuthViewModel.getInstance();
  });

  async function handleAuth() {
    isLoading = true;
    errorMessage = '';
    try {
      const tokenData = await todoVm.getMatrixOpenIdToken();
      await todoVm.authenticateWithTodoService(tokenData);
    } catch (e: any) {
      errorMessage = e?.message ?? 'Unknown error occurred';
    } finally {
      isLoading = false;
    }
  }
</script>

<div class="mx-auto max-w-md p-4">
  <h2 class="mb-4 text-xl font-bold">Todo Service Authentication</h2>

  <button
    on:click={handleAuth}
    class=" rounded-md border border-transparent bg-indigo-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
    disabled={isLoading}
  >
    {#if isLoading}
      Authenticating...
    {:else}
      Authenticate with Matrix
    {/if}
  </button>

  {#if errorMessage}
    <div class="mt-4 text-red-500">Error: {errorMessage}</div>
  {:else}
    <div class="mt-4">
      <p>Status: {todoVm?.authStatus}</p>
    </div>
  {/if}
</div>
