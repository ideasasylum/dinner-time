# frozen_string_literal: true
require_relative "web_push"

# Fans one alert out to every subscribed browser as a native notification. Runs from a request (the test
# button) and from a plan's timer in the worker, which can read `db` too because the objects' registry is
# the app database.
module Alerts
  def self.subject = Melee.env("VAPID_SUBJECT", "mailto:dinner-time@example.invalid")

  def self.subscriptions = db.query("SELECT id, endpoint, p256dh, auth, label, created_at, last_sent_at, last_status, last_error FROM push_subscriptions ORDER BY id")

  def self.count
    row = db.first("SELECT COUNT(*) AS c FROM push_subscriptions")
    row.nil? ? 0 : row["c"].to_i
  end

  def self.subscribe(endpoint, p256dh, auth, label)
    db.run "INSERT INTO push_subscriptions (endpoint, p256dh, auth, label, created_at) VALUES (?, ?, ?, ?, ?) " \
           "ON CONFLICT(endpoint) DO UPDATE SET p256dh = excluded.p256dh, auth = excluded.auth, label = excluded.label",
           endpoint, p256dh, auth, label, Time.now.to_i
    nil
  end

  def self.unsubscribe(endpoint) = db.run("DELETE FROM push_subscriptions WHERE endpoint = ?", endpoint)

  # Sends to everyone and returns how many the push service accepted. A 404 or 410 drops that subscription; a
  # service that cannot be reached is recorded on the row and kept for next time. The detail goes to the log,
  # which works from a plan's timer in the worker too.
  def self.broadcast(title, body, url, tag)
    payload = JSON.generate({ "title" => title, "body" => body, "url" => url, "tag" => tag })
    sent = 0
    subscriptions.each do |s|
      status = 0
      error = ""
      begin
        status = WebPush.deliver(s["endpoint"].to_s, s["p256dh"].to_s, s["auth"].to_s, payload, subject)
        error = "push service answered #{status}" unless status >= 200 && status < 300
      rescue Melee::HTTP::Error => e
        error = "could not reach the push service"
        log.warn "push failed", label: s["label"].to_s, error: e.message
      end
      if WebPush.gone?(status)
        db.run "DELETE FROM push_subscriptions WHERE id = ?", s["id"]
      else
        db.run "UPDATE push_subscriptions SET last_sent_at = ?, last_status = ?, last_error = ? WHERE id = ?", Time.now.to_i, status, error, s["id"]
        sent += 1 if error.empty?
      end
    end
    sent
  end
end
