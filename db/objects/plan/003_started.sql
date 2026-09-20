-- When a step actually began, as opposed to when the plan wanted it to. Without this a timer runs on the
-- plan's clock: put the beef in twelve minutes late and the board still promises it out at the old time.
ALTER TABLE steps ADD COLUMN started_at INTEGER;
