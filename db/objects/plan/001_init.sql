CREATE TABLE dishes (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  position INTEGER NOT NULL
);

CREATE TABLE steps (
  id INTEGER PRIMARY KEY,
  dish_id INTEGER NOT NULL REFERENCES dishes(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  minutes INTEGER NOT NULL DEFAULT 0,
  place TEXT NOT NULL DEFAULT '',
  hands INTEGER NOT NULL DEFAULT 0,
  position INTEGER NOT NULL,
  done_at INTEGER,
  alerted_at INTEGER
);
CREATE INDEX steps_dish ON steps (dish_id, position);
