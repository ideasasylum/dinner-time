-- A timer that finishes is its own alert: the beef comes out of the oven whether or not anything else starts.
-- Only unattended steps get one, so a hands-on step does not nag the cook who is already holding the knife.
ALTER TABLE steps ADD COLUMN end_alerted_at INTEGER;
