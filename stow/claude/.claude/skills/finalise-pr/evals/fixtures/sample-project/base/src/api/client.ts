import { Config } from './config';

export class ApiClient {
  private baseUrl: string;

  constructor(config: Config) {
    this.baseUrl = config.baseUrl;
  }

  async get(path: string): Promise<Response> {
    return fetch(`${this.baseUrl}${path}`);
  }

  async post(path: string, body: unknown): Promise<Response> {
    return fetch(`${this.baseUrl}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
  }
}
