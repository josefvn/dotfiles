# Simplified technical English

Practical subset of ASD-STE100 for commit subjects, PR titles, and PR descriptions.

---

## Rules

1. One idea per sentence.
2. Maximum around 20 words per sentence. Procedural sentences shorter.
3. Active voice. The subject does the action.
4. Simple present or imperative. Avoid perfect and continuous tenses.
5. Use one word for one meaning, consistently. Do not vary "remove", "delete", and "drop" for the same action within one PR.
6. Prefer a simple verb over a noun phrase.
7. Avoid `-ing` forms where a simple verb works.
8. No idioms, no metaphor, no humour, no filler ("basically", "simply", "just").
9. Spell out what a thing does rather than naming it vaguely.
10. Keep articles (a, the) — do not drop them telegram-style.

---

## Examples

### Commit subjects

**Bad:** Basically fixing the thing that was causing issues with retry
**Good:** fix(api): stop the retry loop after three failures

**Bad:** Added some stuff for handling the edge case where tokens are expired
**Good:** feat(auth): reject requests when the token has expired

**Bad:** Misc improvements and cleanup of the database layer
**Good:** refactor(db): extract connection pooling into a separate module

### PR descriptions

**Bad:** This PR basically implements a new feature that allows users to be able to configure their notification preferences, which was something that had been requested by multiple stakeholders.

**Good:** Users can now set their notification preferences. The settings page shows email, push, and SMS options. Each option saves independently.

### Key substitutions

| Avoid | Use instead |
|-------|------------|
| perform configuration of | configure |
| make utilisation of | use |
| is responsible for handling | handles |
| in order to | to |
| at this point in time | now |
| a number of | several / three / many (be specific) |
| it should be noted that | (delete — state the fact directly) |
