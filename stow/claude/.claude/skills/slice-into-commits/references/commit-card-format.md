# Commit card format

When presenting a commit to the user for approval, print it in this exact card shape:

```
Commit 2 of 5
feat(api): add token refresh to the http client

Complete files
  src/api/refresh-token.ts      new file, 62 lines
  src/api/index.ts              +3 -0

Part of a file
  src/api/client.ts             2 of 5 hunks
    L45-L78    refreshToken() and the 401 retry
    L120-L131  hooks the refresh into the request interceptor

Not in this commit
  src/api/client.ts  L12-L20    logging change, goes to commit 5
  tests/client.test.ts          goes to commit 3

Why: the client can renew an expired token without a new login.
Needs first: commit 1 (adds the AuthConfig type)
```

## Rules

- "Not in this commit" is **mandatory** when a file is split or deliberately deferred. This makes the skill's decisions verifiable — the user can see what was left out and why.
- "Part of a file" section disappears when every file in the commit is staged whole.
- "Needs first" only appears when there is a real compile-time or import dependency on a prior commit.
- Keep "Why" to one or two sentences in simplified English.
- List line ranges (L-prefixed) for partial files so the user can verify.

## Plan presentation format

When showing the full commit plan:

```
# feat(api): renew tokens without a new login

Five commits. The client can now refresh an expired token and retry the failed request.

1. feat(api): add the AuthConfig type
2. feat(api): add token refresh to the http client
3. test(api): add tests for token refresh
4. fix(web): show a message when the refresh fails
5. style(web): apply formatter to touched files

Reply with a number to start, or tell me to change the plan.
```

The heading becomes the PR title. The paragraph summarises the overall change.
