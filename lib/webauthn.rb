# frozen_string_literal: true
require_relative "b64"

# The two WebAuthn ceremonies, verified against the bytes the browser hands over.
#
# Registration normally means decoding CBOR twice: the attestation object, and the COSE key buried inside it.
# This decodes neither. `response.getPublicKey()` returns the key as SPKI DER and `getAuthenticatorData()`
# returns the authenticator data on its own, so nothing here parses a binary format off the network. What
# that costs is attestation — this cannot tell you *which* authenticator made a key — and no consumer app
# wants that, because with `attestation: "none"` nobody was checking the authenticator's provenance anyway.
# Registration binds a key the user just made, which is what registration is for.
#
# Nothing here knows what a user is. Verification returns the credential, the user handle the authenticator
# stored and the new signature counter; the app decides whom those belong to. That is what keeps this usable
# by a multi-user app: a passkey names its owner through the handle, so nobody types a username.
module WebAuthn
  ES256 = -7
  CHALLENGE_BYTES = 32
  CHALLENGE_LIFE = 300      # seconds a challenge stays good for
  SPKI_LEN = 91             # a P-256 SubjectPublicKeyInfo, whose last 65 bytes are the uncompressed point
  POINT_LEN = 65
  COORD_LEN = 32
  AUTH_MIN = 37             # rpIdHash(32) + flags(1) + signCount(4)
  FLAG_USER_PRESENT = 0x01
  FLAG_USER_VERIFIED = 0x04

  def self.challenge = B64.encode(SecureRandom.random_bytes(CHALLENGE_BYTES))

  def self.fresh?(minted_at, now) = minted_at.positive? && now - minted_at <= CHALLENGE_LIFE

  # What the browser needs to make a credential. `user_handle` is the opaque id the authenticator keeps and
  # hands back at login; `residentKey: required` is what makes it keep one at all, and so what lets somebody
  # sign in without first saying who they are.
  def self.registration_options(rp_id, rp_name, user_handle, user_name, display_name, challenge, exclude_ids)
    { "challenge" => challenge,
      "rp" => { "id" => rp_id, "name" => rp_name },
      "user" => { "id" => user_handle, "name" => user_name, "displayName" => display_name },
      "pubKeyCredParams" => [{ "type" => "public-key", "alg" => ES256 }],
      "authenticatorSelection" => { "residentKey" => "required", "userVerification" => "preferred" },
      "excludeCredentials" => exclude_ids.map { |id| { "type" => "public-key", "id" => id } },
      "attestation" => "none",
      "timeout" => 120_000 }
  end

  # No allowCredentials: the browser offers whichever passkeys it holds for this site, and the assertion
  # comes back saying which one and whose.
  def self.assertion_options(rp_id, challenge)
    { "challenge" => challenge, "rpId" => rp_id, "userVerification" => "preferred", "timeout" => 120_000 }
  end

  # -> { "ok" => true, "public_key" => <base64url point>, "sign_count" => Integer }
  #    { "ok" => false, "error" => String }
  def self.verify_registration(rp_id, origin, challenge, client_data, authenticator_data, public_key)
    checked = check_client_data(client_data, "webauthn.create", challenge, origin)
    return checked unless checked["ok"]
    auth = B64.decode_or_empty(authenticator_data)
    problem = check_authenticator(auth, rp_id)
    return refuse(problem) unless problem.empty?
    point = public_key_point(B64.decode_or_empty(public_key))
    return refuse("that passkey is not the kind of key this app can check") if point.empty?
    { "ok" => true, "public_key" => B64.encode(point), "sign_count" => sign_count(auth) }
  end

  # -> { "ok" => true, "sign_count" => Integer } | { "ok" => false, "error" => String }
  # `stored_key` is the base64url point kept at registration; `stored_count` the counter last seen.
  def self.verify_assertion(rp_id, origin, challenge, client_data, authenticator_data, signature, stored_key, stored_count)
    checked = check_client_data(client_data, "webauthn.get", challenge, origin)
    return checked unless checked["ok"]
    auth = B64.decode_or_empty(authenticator_data)
    problem = check_authenticator(auth, rp_id)
    return refuse(problem) unless problem.empty?
    raw = B64.decode_or_empty(client_data)
    return refuse("client data is malformed") if raw.empty?
    signed = auth + OpenSSL::Digest::SHA256.digest(raw)
    sig = raw_signature(B64.decode_or_empty(signature))
    return refuse("that signature is malformed") if sig.empty?
    return refuse("that signature does not match this passkey") unless signed_by?(stored_key, sig, signed)
    count = sign_count(auth)
    # Apple and Google authenticators always report zero, so a counter only means something when both sides
    # have one. When they do, a counter that has not moved is the signature of a cloned key.
    return refuse("that passkey looks like a copy") if count.positive? && stored_count.positive? && count <= stored_count
    { "ok" => true, "sign_count" => count }
  end

  def self.refuse(message) = { "ok" => false, "error" => message }

  def self.signed_by?(stored_key, signature, signed)
    point = B64.decode_or_empty(stored_key)
    return false if point.empty?
    OpenSSL::PKey::EC.from_public_bytes("prime256v1", point).verify_raw("SHA256", signature, signed)
  rescue OpenSSL::PKey::ECError
    false
  end

  # The browser's own record of the ceremony: what kind it was, which challenge it answered, and which site
  # asked. The origin check is the one that stops a look-alike site relaying a ceremony to this one.
  def self.check_client_data(encoded, expected_type, challenge, origin)
    raw = B64.decode_or_empty(encoded)
    return refuse("client data is malformed") if raw.empty?
    data = JSON.parse(raw)
    return refuse("client data is malformed") unless data.is_a?(Hash)
    return refuse("that was the wrong kind of ceremony") unless data["type"].to_s == expected_type
    return refuse("that challenge is not the one this app issued") unless secure_equal?(data["challenge"].to_s, challenge)
    return refuse("that ceremony came from another site") unless data["origin"].to_s == origin
    { "ok" => true }
  rescue JSON::ParserError
    refuse("client data is not JSON")
  end

  # rpIdHash(32) || flags(1) || signCount(4), then things this app does not read. Returns "" when it is good.
  def self.check_authenticator(auth, rp_id)
    return "the authenticator data is malformed" if auth.bytesize < AUTH_MIN
    return "that passkey belongs to another site" unless secure_equal?(auth.byteslice(0, 32).to_s, OpenSSL::Digest::SHA256.digest(rp_id))
    return "nobody was there to approve that" if flags(auth) & FLAG_USER_PRESENT == 0
    ""
  end

  # byteslice answers String-or-nil, so every read is pinned back to a String before anything is asked of it.
  def self.flags(auth) = auth.byteslice(32, 1).to_s.unpack1("C").to_i

  def self.sign_count(auth) = auth.byteslice(33, 4).to_s.unpack1("N").to_i

  def self.verified?(auth) = flags(auth) & FLAG_USER_VERIFIED != 0

  # A P-256 SubjectPublicKeyInfo is a fixed 91 bytes whose tail is the uncompressed point, so the key arrives
  # in exactly the shape OpenSSL::PKey::EC.from_public_bytes wants. Both facts are checked rather than assumed.
  def self.public_key_point(spki)
    return "" if spki.bytesize != SPKI_LEN
    point = spki.byteslice(SPKI_LEN - POINT_LEN, POINT_LEN).to_s
    point.start_with?("\x04") ? point : ""
  end

  # Browsers emit an ECDSA signature DER-encoded; melee verifies raw r || s. DER integers are signed, so each
  # half may carry a leading zero to keep it positive, and may be short if it has leading zero bytes of its
  # own — hence strip, then left-pad to the curve's width.
  def self.raw_signature(der)
    return "" if der.bytesize < 8 || !der.start_with?("\x30") || byte_at(der, 1) != der.bytesize - 2
    out = +""
    at = 2
    2.times do
      return "" unless byte_at(der, at) == 0x02
      width = byte_at(der, at + 1)
      value = der.byteslice(at + 2, width).to_s
      return "" if value.bytesize != width
      from = 0
      from += 1 while from < value.bytesize && byte_at(value, from) == 0
      trimmed = value.byteslice(from, value.bytesize - from).to_s
      return "" if trimmed.empty? || trimmed.bytesize > COORD_LEN
      out << "\x00" * (COORD_LEN - trimmed.bytesize) << trimmed
      at += 2 + width
    end
    at == der.bytesize ? out : ""
  end

  def self.byte_at(text, index) = text.byteslice(index, 1).to_s.unpack1("C").to_i
end
