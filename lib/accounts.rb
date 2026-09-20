# frozen_string_literal: true
require_relative "b64"
require_relative "webauthn"

# The app's side of WebAuthn: who exists, which passkeys are theirs, and the two ceremonies wired to the
# database. WebAuthn itself stays user-agnostic; this is where a credential becomes a person.
#
# The first account is the awkward one. This app's address is already public, so "whoever registers first
# wins" would hand it to a stranger. Setup therefore needs a secret set with `melee env`, and only works
# while there are no users at all. After that a second device is enrolled from inside the signed-in app.
module Accounts
  # An account with no passkey is not an account: nobody can open it, and leaving setup shut in that state
  # would brick the app if a ceremony failed halfway. So "claimed" means a credential exists, and setup
  # reuses the half-made account rather than piling up another.
  def self.claimed?
    row = db.first("SELECT COUNT(*) AS c FROM credentials")
    !row.nil? && row["c"].to_i.positive?
  end

  def self.unclaimed
    db.first "SELECT u.id, u.handle, u.name FROM users u " \
             "LEFT JOIN credentials c ON c.user_id = u.id WHERE c.id IS NULL ORDER BY u.id LIMIT 1"
  end

  def self.setup_secret = Melee.env("SETUP_SECRET", "")

  def self.claim(name)
    waiting = unclaimed
    return waiting["id"].to_i unless waiting.nil?
    create(name)
  end

  def self.create(name)
    db.run "INSERT INTO users (handle, name, created_at) VALUES (?, ?, ?)",
           B64.encode(SecureRandom.random_bytes(16)), name, Time.now.to_i
    db.last_id
  end

  def self.find(id) = db.first("SELECT id, handle, name FROM users WHERE id = ?", id.to_i)

  def self.by_handle(handle) = db.first("SELECT id, handle, name FROM users WHERE handle = ?", handle.to_s)

  def self.credentials(user_id)
    db.query "SELECT id, credential_id, public_key, sign_count, label, created_at, last_used_at " \
             "FROM credentials WHERE user_id = ? ORDER BY id", user_id.to_i
  end

  def self.credential(credential_id)
    db.first "SELECT c.id, c.user_id, c.credential_id, c.public_key, c.sign_count, c.label, u.handle " \
             "FROM credentials c JOIN users u ON u.id = c.user_id WHERE c.credential_id = ?", credential_id.to_s
  end

  def self.forget(user_id, id) = db.run("DELETE FROM credentials WHERE id = ? AND user_id = ?", id.to_i, user_id.to_i)

  # Registration, end to end. Returns the WebAuthn result Hash, with the credential stored when it passed.
  def self.register(user_id, rp_id, origin, challenge, params, label)
    result = WebAuthn.verify_registration(rp_id, origin, challenge,
                                          params.fetch(:client_data), params.fetch(:authenticator_data),
                                          params.fetch(:public_key))
    return result unless result["ok"]
    credential_id = params.fetch(:credential_id)
    return WebAuthn.refuse("that passkey is registered already") unless credential(credential_id).nil?
    db.run "INSERT INTO credentials (user_id, credential_id, public_key, sign_count, label, created_at) " \
           "VALUES (?, ?, ?, ?, ?, ?)",
           user_id.to_i, credential_id, result["public_key"], result["sign_count"].to_i, label, Time.now.to_i
    result
  end

  # A login. Returns { "ok" => true, "user_id" => Integer } or the refusal.
  def self.authenticate(rp_id, origin, challenge, params)
    stored = credential(params.fetch(:credential_id))
    return WebAuthn.refuse("this app does not know that passkey") if stored.nil?
    # The handle the authenticator kept has to name the same account the credential does, or a passkey could
    # be replayed against somebody else's row.
    handle = params.fetch(:user_handle)
    return WebAuthn.refuse("that passkey belongs to another account") unless handle.empty? || handle == stored["handle"].to_s
    result = WebAuthn.verify_assertion(rp_id, origin, challenge,
                                       params.fetch(:client_data), params.fetch(:authenticator_data),
                                       params.fetch(:signature), stored["public_key"].to_s, stored["sign_count"].to_i)
    return result unless result["ok"]
    db.run "UPDATE credentials SET sign_count = ?, last_used_at = ? WHERE id = ?",
           result["sign_count"].to_i, Time.now.to_i, stored["id"]
    { "ok" => true, "user_id" => stored["user_id"].to_i }
  end
end
