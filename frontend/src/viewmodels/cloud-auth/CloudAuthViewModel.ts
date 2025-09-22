import { MatrixViewModel } from '../matrix/MatrixViewModel';
import type { IOpenIDToken } from 'matrix-js-sdk';
import { DefaultApi } from '../../api/generated/apis';
import type { MatrixAuthResponse, MatrixOpenIDRequest } from '../../api/generated/models';

export class CloudAuthViewModel {
  private static instance: CloudAuthViewModel | null = null;
  private matrix: MatrixViewModel;
  public authStatus: string = 'Not authenticated';
  public jwtToken: string | null = null;
  public userID: string | null = null;
  public mxid: string | null = null;
  private tokenExpiresAt: number | null = null;
  private refreshTimer: ReturnType<typeof setTimeout> | null = null;
  private refreshPromise: Promise<void> | null = null;
  private readonly REFRESH_LEEWAY_MS = 5 * 60 * 1000; // 5 minutes

  private constructor() {
    this.matrix = MatrixViewModel.getInstance();
    const storedResponse = localStorage.getItem('cloud_auth');
    if (storedResponse) {
      try {
        const response: MatrixAuthResponse & { expiresAt?: number } = JSON.parse(storedResponse);
        this.applySession(response);
      } catch {
        // fallback to old token-only storage for backward compatibility
        const storedToken = localStorage.getItem('cloud_jwt');
        if (storedToken) {
          this.jwtToken = storedToken;
          this.authStatus = 'Already authenticated';
          this.tokenExpiresAt = this.decodeTokenExpiry(storedToken);
          if (!this.tokenExpiresAt) {
            void this.refreshToken().catch((err) => {
              console.error('[CloudAuthViewModel] token refresh failed', err);
            });
          } else {
            this.scheduleRefresh();
          }
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
      this.applySession(response);
    } catch (error) {
      this.authStatus = `Auth failed: ${error}`;
      throw error;
    }
  }

  public async ensureValidSession(): Promise<void> {
    if (!this.jwtToken) {
      await this.refreshToken();
      return;
    }
    if (this.tokenExpiresAt == null) {
      await this.refreshToken();
      return;
    }
    const remaining = this.tokenExpiresAt - Date.now();
    if (remaining <= this.REFRESH_LEEWAY_MS) {
      await this.refreshToken();
    }
  }

  public clearSession(): void {
    this.jwtToken = null;
    this.mxid = null;
    this.userID = null;
    this.tokenExpiresAt = null;
    this.clearRefreshTimer();
    localStorage.removeItem('cloud_auth');
    localStorage.removeItem('cloud_jwt');
    this.authStatus = 'Not authenticated';
  }

  private applySession(response: MatrixAuthResponse & { expiresAt?: number }): void {
    this.jwtToken = response.token || null;
    this.mxid = response.mxid || null;
    this.userID = response.userId || null;
    this.tokenExpiresAt =
      typeof response.expiresAt === 'number' ? response.expiresAt : this.decodeTokenExpiry(response.token);

    const stored = {
      ...response,
      expiresAt: this.tokenExpiresAt ?? undefined,
    };
    localStorage.setItem('cloud_auth', JSON.stringify(stored));
    if (this.jwtToken) {
      localStorage.setItem('cloud_jwt', this.jwtToken);
    }

    this.authStatus = 'Authenticated with Backend Service';
    if (this.tokenExpiresAt) {
      this.scheduleRefresh();
    }
  }

  private decodeTokenExpiry(token: string | null): number | null {
    if (!token) return null;
    const parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      const payloadBase64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      const padded = payloadBase64.padEnd(payloadBase64.length + ((4 - (payloadBase64.length % 4)) % 4), '=');
      const payload = JSON.parse(atob(padded));
      if (payload && typeof payload.exp === 'number') {
        return payload.exp * 1000;
      }
    } catch (error) {
      console.warn('[CloudAuthViewModel] Failed to decode token expiry', error);
    }
    return null;
  }

  private scheduleRefresh(): void {
    this.clearRefreshTimer();
    if (!this.tokenExpiresAt) {
      return;
    }
    const delay = Math.max(this.tokenExpiresAt - Date.now() - this.REFRESH_LEEWAY_MS, 0);
    if (delay <= 0) {
      void this.refreshToken().catch((err) => console.error('[CloudAuthViewModel] token refresh failed', err));
      return;
    }
    this.refreshTimer = setTimeout(() => {
      void this.refreshToken().catch((err) => console.error('[CloudAuthViewModel] token refresh failed', err));
    }, delay);
  }

  private clearRefreshTimer(): void {
    if (this.refreshTimer) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = null;
    }
  }

  private async refreshToken(): Promise<void> {
    if (this.refreshPromise) {
      return this.refreshPromise;
    }
    this.refreshPromise = (async () => {
      try {
        const tokenData = await this.getMatrixOpenIdToken();
        await this.authenticateWithTodoService(tokenData);
      } catch (error) {
        this.authStatus = `Token refresh failed: ${error}`;
        this.clearSession();
        throw error;
      } finally {
        this.refreshPromise = null;
      }
    })();
    return this.refreshPromise;
  }
}
