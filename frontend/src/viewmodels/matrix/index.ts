import { USE_MATRIX_LITE } from '@/matrix-lite/flag';
import { MatrixLiteViewModel } from './MatrixLiteViewModel';
import { MatrixViewModel as SdkMatrixViewModel } from './MatrixSdkViewModel';

// Export the appropriate implementation based on the flag.
// Consumers can always import { MatrixViewModel } from '@/viewmodels/matrix'.
const MatrixViewModel = USE_MATRIX_LITE ? MatrixLiteViewModel : (SdkMatrixViewModel as any);
export { MatrixViewModel };
