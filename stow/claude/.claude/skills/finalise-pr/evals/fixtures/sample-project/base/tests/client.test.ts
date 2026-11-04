import { ApiClient } from '../src/api/client';

describe('ApiClient', () => {
  it('should make GET requests', async () => {
    const client = new ApiClient({ baseUrl: 'http://localhost', timeout: 1000 });
    // placeholder test
    expect(client).toBeDefined();
  });
});
