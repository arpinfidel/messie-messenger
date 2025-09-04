import { MatrixSdkViewModel } from './MatrixSdkViewModel';
import { MatrixLiteViewModel } from './MatrixLiteViewModel';

// Global compile-time flag provided by Vite
declare const USE_MATRIX_LITE: boolean;

export const MatrixViewModel = USE_MATRIX_LITE ? MatrixLiteViewModel : MatrixSdkViewModel;
