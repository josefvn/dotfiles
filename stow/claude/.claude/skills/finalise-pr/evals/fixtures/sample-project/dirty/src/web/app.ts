import { ApiClient } from '../api/client';
import { defaultConfig } from '../api/config';

const client = new ApiClient(defaultConfig);

export async function loadUsers() {
  const response = await client.get('/users');
  if (!response.ok) {
    throw new Error(`Failed to load users: ${response.status}`);
  }
  return response.json();
}

export async function loadProfile(userId: string) {
  const response = await client.get(`/users/${userId}`);
  if (!response.ok) {
    throw new Error(`Failed to load profile: ${response.status}`);
  }
  return response.json();
}
