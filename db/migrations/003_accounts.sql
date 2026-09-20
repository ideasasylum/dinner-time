-- Who may use this app, and the passkeys that prove it. `handle` is the opaque id WebAuthn stores on the
-- authenticator and hands back at login, which is how a passkey names its owner with nobody typing a name.
-- One row today; the shape is the one a multi-user app needs, so adding people later is a migration rather
-- than a rewrite.
CREATE TABLE users (
  id INTEGER PRIMARY KEY,
  handle TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE credentials (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  credential_id TEXT NOT NULL UNIQUE,
  public_key TEXT NOT NULL,
  sign_count INTEGER NOT NULL DEFAULT 0,
  label TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  last_used_at INTEGER
);
CREATE INDEX credentials_user ON credentials (user_id);
