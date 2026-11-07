---
areas: [process, net]
---
# A decision about guests was read without the sign-in code

2026-11-04

- **Saw:** The progression plan read the no-offline-XP decision as nothing earned by a guest, and wrote
  "Sign in to keep your XP" into five issues and the design page. The maintainer meant the opposite: a Guest account
  is tracked on the server and earns. They also said guests last 7 days and return through local storage, which the
  code does not do: `/auth/guest` makes a new account each time, and the token stays in memory.
- **Cause:** "Guest" had a plain meaning, so nobody opened the sign-in code. The reading was marked "to confirm", but
  the issues were filed on it anyway, and one agent had started before the answer came.
- **Fix:** Issues #1058, #1066, #1068, #1075 and #1077 were corrected, the design page follows in #1058's pull
  request, and #1080 builds the Guest account the maintainer described.
- **Check next time:** Before a rule turns on what kind of person is playing, read how that kind of account signs in
  and what it can do today. A maintainer's description of how something works is checked against the code as well, and
  a difference is reported and filed, never assumed either way.
