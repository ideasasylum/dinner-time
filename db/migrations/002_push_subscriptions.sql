-- One row per browser that asked for alerts. The keys are the subscription's base64url strings as the
-- browser hands them over; last_status and last_error record how the most recent send went.
CREATE TABLE push_subscriptions (
  id INTEGER PRIMARY KEY,
  endpoint TEXT NOT NULL UNIQUE,
  p256dh TEXT NOT NULL,
  auth TEXT NOT NULL,
  label TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  last_sent_at INTEGER,
  last_status INTEGER,
  last_error TEXT
);
