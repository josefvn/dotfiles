export function renderAuthStatus(isLoggedIn: boolean): string {
  if (isLoggedIn) {
    return '<span class="status">Logged in</span>';
  }
  return '<a href="/login">Log in</a>';
}
