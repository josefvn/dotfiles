import { Config } from './config';
import { AuthToken, isExpired, refreshAuth } from './auth';

export class ApiClient {
  private baseUrl: string;
  private token: AuthToken | null = null;

  constructor(config: Config) {
    console.log('[ApiClient] initialising with base URL:', config.baseUrl);
    this.baseUrl = config.baseUrl;
  }

  setToken(token: AuthToken) {
    this.token = token;
  }

  private async ensureFreshToken(): Promise<void> {
    if (this.token && isExpired(this.token)) {
      this.token = await refreshAuth(this.token);
    }
  }

  private getHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };
    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token.accessToken}`;
    }
    return headers;
  }

  async get(path: string): Promise<Response> {
    await this.ensureFreshToken();
    console.log('[ApiClient] GET', path);
    return fetch(`${this.baseUrl}${path}`, {
      headers: this.getHeaders(),
    });
  }

  async post(path: string, body: unknown): Promise<Response> {
    await this.ensureFreshToken();
    console.log('[ApiClient] POST', path);
    return fetch(`${this.baseUrl}${path}`, {
      method: 'POST',
      headers: this.getHeaders(),
      body: JSON.stringify(body),
    });
  }
}
