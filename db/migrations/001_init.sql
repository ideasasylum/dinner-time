-- The list of plans. Each plan's dishes, steps and timer live in its own durable object (db/objects/plan/).
CREATE TABLE plans (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  serve_at INTEGER NOT NULL,
  tz_offset INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);
