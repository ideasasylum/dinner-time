# frozen_string_literal: true
# Web Push from the server: RFC 8291 payload encryption (aes128gcm) and RFC 8292 VAPID, over Melee::HTTP.
# One keypair for the app, stored with `setting`; one ephemeral keypair per message. The same code runs under
# CRuby (with melee's EC shim) and in the compiled binary, where these are Spinel's own openssl methods.
module WebPush
  CURVE = "prime256v1"
  RECORD_SIZE = 4096
  TOKEN_LIFE = 12 * 3600

  def self.b64u(bin) = Base64.urlsafe_encode64(bin, padding: false)

  def self.unb64u(text)
    padded = text + "=" * ((4 - text.bytesize % 4) % 4)
    Base64.urlsafe_decode64(padded)
  end

  # The app's VAPID keypair as base64url, minted on first use. "public" is what the browser subscribes with.
  def self.keys
    priv = setting("vapid_private").to_s
    if priv.empty?
      key = OpenSSL::PKey::EC.generate(CURVE)
      priv = setting("vapid_private", b64u(key.private_key_bytes))
      setting("vapid_public", b64u(key.public_key_bytes))
    end
    { "private" => priv, "public" => setting("vapid_public").to_s }
  end

  def self.public_key = keys["public"]

  # RFC 8291 section 3: the whole aes128gcm body (header, one record, tag) for one subscription.
  def self.encrypt(plaintext, ua_public, auth, as_key, salt)
    secret = as_key.dh_compute_key(ua_public)
    ikm = OpenSSL::KDF.hkdf(secret, salt: auth, info: "WebPush: info\0" + ua_public + as_key.public_key_bytes, length: 32, hash: "SHA256")
    cek = OpenSSL::KDF.hkdf(ikm, salt: salt, info: "Content-Encoding: aes128gcm\0", length: 16, hash: "SHA256")
    nonce = OpenSSL::KDF.hkdf(ikm, salt: salt, info: "Content-Encoding: nonce\0", length: 12, hash: "SHA256")
    cipher = OpenSSL::Cipher.new("aes-128-gcm")
    cipher.encrypt
    cipher.key = cek
    cipher.iv = nonce
    cipher.auth_data = ""
    record = cipher.update(plaintext + "\x02") + cipher.final + cipher.auth_tag
    as_public = as_key.public_key_bytes
    salt + [RECORD_SIZE].pack("N") + [as_public.bytesize].pack("C") + as_public + record
  end

  # RFC 8292: "vapid t=<jwt>, k=<public key>" for the push service that owns `endpoint`.
  def self.authorization(endpoint, private_b64u, public_b64u, subject, now)
    uri = URI.parse(endpoint)
    aud = uri.port == uri.default_port ? "#{uri.scheme}://#{uri.host}" : "#{uri.scheme}://#{uri.host}:#{uri.port}"
    header = b64u(%({"typ":"JWT","alg":"ES256"}))
    claims = b64u(%({"aud":"#{aud}","exp":#{now + TOKEN_LIFE},"sub":"#{subject}"}))
    key = OpenSSL::PKey::EC.from_private_bytes(CURVE, unb64u(private_b64u))
    signature = key.sign_raw("SHA256", "#{header}.#{claims}")
    "vapid t=#{header}.#{claims}.#{b64u(signature)}, k=#{public_b64u}"
  end

  # Delivers `payload` (a String, usually JSON) to one subscription and returns the push service's status:
  # 201 is accepted, 404 or 410 means the subscription is dead and should be dropped. Raises
  # Melee::HTTP::Error when the service cannot be reached.
  def self.deliver(endpoint, p256dh, auth, payload, subject, ttl = 300)
    vapid = keys
    as_key = OpenSSL::PKey::EC.generate(CURVE)
    body = encrypt(payload, unb64u(p256dh), unb64u(auth), as_key, SecureRandom.random_bytes(16))
    headers = {
      "Authorization" => authorization(endpoint, vapid["private"], vapid["public"], subject, Time.now.to_i),
      "Content-Encoding" => "aes128gcm",
      "Content-Type" => "application/octet-stream",
      "TTL" => ttl.to_s,
      "Urgency" => "high"
    }
    Melee::HTTP.post(endpoint, body: body, headers: headers, timeout: 10).status
  end

  def self.gone?(status) = status == 404 || status == 410
end
