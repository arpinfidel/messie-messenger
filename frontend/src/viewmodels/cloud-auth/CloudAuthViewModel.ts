import { MatrixViewModel } from '../matrix/MatrixViewModel';
import type { IOpenIDToken } from 'matrix-js-sdk';
import { DefaultApi } from '../../api/generated/apis';
import type { MatrixOpenIDRequest } from '../../api/generated/models';

export class CloudAuthViewModel {
  private static instance: CloudAuthViewModel | null = null;
  private matrix: MatrixViewModel;
  public authStatus: string = 'Not authenticated';
  public jwtToken: string | null = null;
  public userID: string | null = null;
  public mxid: string | null = null;

  private constructor() {
    this.matrix = MatrixViewModel.getInstance();
    const storedResponse = localStorage.getItem('cloud_auth');
    if (storedResponse) {
      try {
        const response = JSON.parse(storedResponse);
        this.jwtToken = response.token || null;
        this.mxid = response.mxid || null;
        this.userID = response.userId || null;
        this.authStatus = 'Already authenticated';
      } catch {
        // fallback to old token-only storage for backward compatibility
        const storedToken = localStorage.getItem('cloud_jwt');
        if (storedToken) {
          this.jwtToken = storedToken;
          this.authStatus = 'Already authenticated';
        }
      }
    }
  }

  public static getInstance(): CloudAuthViewModel {
    if (!CloudAuthViewModel.instance) {
      CloudAuthViewModel.instance = new CloudAuthViewModel();
    }
    return CloudAuthViewModel.instance;
  }

  async getMatrixOpenIdToken(): Promise<IOpenIDToken> {
    try {
      const tokenData = await this.matrix.getOpenIdToken();
      this.authStatus = 'Obtained Matrix OpenID token';
      return tokenData;
    } catch (error) {
      this.authStatus = `Error getting token: ${error}`;
      throw error;
    }
  }

  async authenticateWithTodoService(tokenData: IOpenIDToken): Promise<void> {
    try {
      const api = new DefaultApi();
      const request: MatrixOpenIDRequest = {
        accessToken: tokenData.access_token,
        matrixServerName: tokenData.matrix_server_name,
      };

      const response = await api.postMatrixAuth({ matrixOpenIDRequest: request });
      console.log('[CloudAuthViewModel] Auth response:', response);

      this.jwtToken = response.token;
      this.mxid = response.mxid;
      this.userID = response.userId;

      localStorage.setItem('cloud_auth', JSON.stringify(response));
      this.authStatus = 'Authenticated with Backend Service';
    } catch (error) {
      this.authStatus = `Auth failed: ${error}`;
      throw error;
    }
  }
}
