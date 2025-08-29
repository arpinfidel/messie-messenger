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

<div class="p-4 max-w-md mx-auto">
  <h2 class="text-xl font-bold mb-4">Todo Service Authentication</h2>
  
  <button 
    on:click={handleAuth}
    class=" py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
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