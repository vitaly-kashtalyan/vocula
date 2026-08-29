# Reporting a security problem

Vocula installs a global event tap, holds Accessibility, pastes into whatever
application is focused, and keeps a year of dictation history encrypted under a
key in your login keychain. A defect in any of those is worth telling me about
before it is public.

**Use GitHub's private vulnerability reporting** — the *Report a vulnerability*
button under this repository's Security tab. It opens a thread only you and I
can read. Please do not open a public issue for anything in the list below.

## In scope

- Reading, decrypting or corrupting the history file, or its keychain key.
- Getting text inserted somewhere that should have been refused — a password
  field, or anything reached while secure input is up.
- Anything that makes the app record or transmit audio outside a dictation.
- Forging a licence, or making the verifier accept one it should not.
- Code execution through a model download, a build script, or a workflow here.

## Not in scope

- Removing the licence check in your own build. The source is GPL-3.0 and that
  is what the licence permits. It is a design decision, not a vulnerability.
- Anything that needs code already running as you on an unlocked Mac. That
  threat model is stated plainly in [PRIVACY.md](PRIVACY.md) and is not
  defended against.
- The dictated text passing through the system pasteboard for about a second.
  It is how insertion works, and PRIVACY.md says so.
- A licence key that keeps working after a refund, or one forwarded to a
  friend. Verification is offline by design, so there is no server to revoke
  against; that trade is deliberate and is what keeps the app from phoning
  home.

## What to expect

One person, not a team. I will acknowledge within a week and say what I intend
to do about it. Pull requests are still not accepted — see
[CONTRIBUTING.md](CONTRIBUTING.md) for why — so send the finding and, if you
have one, the measurement behind it; writing the fix will be my job.
