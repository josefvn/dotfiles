export interface AuthToken {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
}

export function isExpired(token: AuthToken): boolean {
  return Date.now() > token.expiresAt;
}

export async function refreshAuth(token: AuthToken): Promise<AuthToken> {
  const response = await fetch('/auth/refresh', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ refreshToken: token.refreshToken }),
  });
  return response.json();
}
