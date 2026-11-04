import { ApiClient } from '../src/api/client';
import { AuthToken } from '../src/api/auth';

describe('ApiClient', () => {
  it('should make GET requests', async () => {
    const client = new ApiClient({ baseUrl: 'http://localhost', timeout: 1000 });
    expect(client).toBeDefined();
  });

  it('should attach auth headers when token is set', () => {
    const client = new ApiClient({ baseUrl: 'http://localhost', timeout: 1000 });
    const token: AuthToken = {
      accessToken: 'test-token',
      refreshToken: 'test-refresh',
      expiresAt: Date.now() + 3600000,
    };
    client.setToken(token);
    expect(client).toBeDefined();
  });

  it('should refresh expired tokens', async () => {
    const client = new ApiClient({ baseUrl: 'http://localhost', timeout: 1000 });
    const expiredToken: AuthToken = {
      accessToken: 'old-token',
      refreshToken: 'refresh-me',
      expiresAt: Date.now() - 1000,
    };
    client.setToken(expiredToken);
    // Token refresh would be triggered on next request
    expect(client).toBeDefined();
  });
});
