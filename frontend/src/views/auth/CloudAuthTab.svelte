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
    todoVm = new CloudAuthViewModel(matrixVm);
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
    class="btn-primary"
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
      {#if todoVm?.jwtToken}
        <div class="mt-2">
          <p class="break-words">JWT: {todoVm.jwtToken.slice(0, 15)}...</p>
          <p>MXID: {todoVm.mxid}</p>
        </div>
      {/if}
    </div>
  {/if}
</div>