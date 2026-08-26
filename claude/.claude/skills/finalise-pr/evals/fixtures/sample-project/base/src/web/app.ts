import { ApiClient } from '../api/client';
import { defaultConfig } from '../api/config';

const client = new ApiClient(defaultConfig);

export async function loadUsers() {
  const response = await client.get('/users');
  return response.json();
}
