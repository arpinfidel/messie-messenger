import { MatrixViewModel } from '../matrix/MatrixViewModel';
import { MatrixClient, type IOpenIDToken } from 'matrix-js-sdk';

export class CloudAuthViewModel {
  private matrix: MatrixViewModel;
  public authStatus: string = 'Not authenticated';
  public jwtToken: string | null = null;
  public mxid: string | null = null;

  constructor(private matrixViewModel: MatrixViewModel) {
    this.matrix = matrixViewModel;
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
      const response = await fetch('/api/v1/auth/matrix/openid', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          access_token: tokenData.access_token,
          matrix_server_name: tokenData.matrix_server_name
        })
      });

      if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
      
      const { jwt, mxid } = await response.json();
      this.jwtToken = jwt;
      this.mxid = mxid;
      localStorage.setItem('todo_jwt', jwt);
      this.authStatus = 'Authenticated with Todo Service';
      
      console.log('JWT:', jwt);
      console.log('MXID:', mxid);
    } catch (error) {
      this.authStatus = `Auth failed: ${error}`;
      throw error;
    }
  }
}