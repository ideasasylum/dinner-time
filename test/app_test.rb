# frozen_string_literal: true
# `melee test` runs this under CRuby; `melee test --spinel` runs it against the compiled binary.
# Needs a setup secret, the same one the app wants in production: SETUP_SECRET=... melee test
require_relative "../lib/clock"
require_relative "../lib/schedule"
require_relative "../lib/web_push"
require_relative "../lib/webauthn"

TZ = -60 # British Summer Time, as a browser reports it

# Every route but the login pages needs a passkey, so each case signs in first. The authenticator is a Ruby
# key here; the bytes it produces are the ones a Secure Enclave would send, which is what makes this a test
# of the verification rather than of a stub.
TEST_KEY = OpenSSL::PKey::EC.generate("prime256v1")
TEST_CREDENTIAL = B64.encode(SecureRandom.random_bytes(16))
TEST_RP = "app.test"
TEST_ORIGIN = "https://app.test"

# Every ceremony mints fresh randomness — challenges, keys, credential ids, signatures, and the VAPID key —
# so two runs can only be compared with those masked. Long unbroken base64url runs are exactly those values;
# this app's own words are short and spaced, so a real difference in the bytes still shows.
mask(/[A-Za-z0-9_-]{22,}/)

setup do
  get "/login"
  enrol_passkey if body.include?("Claim this app")
  sign_in_with_passkey
end

def enrol_passkey
  post "/auth/setup", secret: ENV.fetch("SETUP_SECRET", ""), name: "Jamie"
  post "/auth/register/options"
  post "/auth/register",
       credential_id: TEST_CREDENTIAL,
       client_data: B64.encode(client_data("webauthn.create", JSON.parse(body)["challenge"], TEST_ORIGIN)),
       authenticator_data: B64.encode(authenticator_data(TEST_RP, 0x45, 0)),
       public_key: B64.encode(spki_for(TEST_KEY)),
       label: "Test device"
end

def sign_in_with_passkey
  post "/auth/login/options"
  a = signed_assertion(TEST_KEY, TEST_RP, JSON.parse(body)["challenge"], TEST_ORIGIN, 0)
  post "/auth/login", credential_id: TEST_CREDENTIAL, client_data: a["client"],
                      authenticator_data: a["auth"], signature: a["sig"], user_handle: ""
end

def roast_dishes = [{ "id" => 1, "name" => "Beef", "position" => 0 }, { "id" => 2, "name" => "Gravy", "position" => 1 }]

def roast_steps
  [
    { "id" => 1, "dish_id" => 1, "name" => "Roast", "minutes" => 90, "place" => "oven1", "hands" => 0, "position" => 0, "done_at" => nil },
    { "id" => 2, "dish_id" => 1, "name" => "Rest", "minutes" => 30, "place" => "", "hands" => 0, "position" => 1, "done_at" => nil },
    { "id" => 3, "dish_id" => 1, "name" => "Carve", "minutes" => 10, "place" => "", "hands" => 1, "position" => 2, "done_at" => nil },
    { "id" => 4, "dish_id" => 2, "name" => "Make the gravy", "minutes" => 15, "place" => "hob", "hands" => 1, "position" => 0, "done_at" => nil }
  ]
end

test "the clock converts a browser date and time to seconds and back without the server's zone" do
  secs = Clock.parse("2026-09-20", "18:00", TZ)
  assert_equal 1_789_923_600, secs
  assert_equal "18:00", Clock.hhmm(secs, TZ)
  assert_equal "Sun 20 Sep", Clock.day_label(secs, TZ)
  assert_equal "2026-09-20", Clock.ymd(secs, TZ)
  assert_equal nil, Clock.parse("20/09/2026", "18:00", TZ)
  assert_equal "1 h 30 min", Clock.duration(90)
end

test "a chain works backwards from the serve time" do
  serve = Clock.parse("2026-09-20", "18:00", TZ)
  placed = Schedule.compute(serve, roast_dishes, roast_steps)
  by_name = {}
  placed.each { |s| by_name[s["name"].to_s] = s }
  assert_equal "17:50", Clock.hhmm(by_name["Carve"]["start_at"].to_i, TZ)
  assert_equal "17:20", Clock.hhmm(by_name["Rest"]["start_at"].to_i, TZ)
  assert_equal "15:50", Clock.hhmm(by_name["Roast"]["start_at"].to_i, TZ)
  assert_equal "Roast", placed.first["name"]
end

test "two hands-on steps never overlap, and the lower dish is the one that moves" do
  serve = Clock.parse("2026-09-20", "18:00", TZ)
  placed = Schedule.compute(serve, roast_dishes, roast_steps)
  gravy = placed.find { |s| s["name"] == "Make the gravy" }
  carve = placed.find { |s| s["name"] == "Carve" }
  assert_equal carve["start_at"], gravy["end_at"]
  assert_equal "17:35", Clock.hhmm(gravy["start_at"].to_i, TZ)
  assert_equal 1, gravy["shifted"]
  assert_equal 0, carve["shifted"]
end

test "the home page offers a new dinner and the alerts card" do
  get "/"
  assert_equal 200, status
  assert body.include?("New dinner")
  assert body.include?("Enable alerts on this device")
end

# RFC 8291 section 5, so the bytes on the wire are the RFC's and not just self-consistent.
def hx(s) = [s].pack("H*")

test "push payloads are encrypted exactly as RFC 8291 says, and the VAPID token verifies" do
  as_key = OpenSSL::PKey::EC.from_private_bytes("prime256v1", hx("c9f58f89813e9f8e872e71f42aa64e1757c9254dcc62b72ddc010bb4043ea11c"))
  ua_pub = hx("042571b2becdfde360551aaf1ed0f4cd366c11cebe555f89bcb7b186a53339173168ece2ebe018597bd30479b86e3c8f8eced577ca59187e9246990db682008b0e")
  body = WebPush.encrypt("When I grow up, I want to be a watermelon", ua_pub, hx("05305932a1c7eabe13b6cec9fda48882"), as_key, hx("0c6bfaadad67958803092d454676f397"))
  assert_equal "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN", WebPush.b64u(body)

  auth = WebPush.authorization("https://web.push.apple.com/QAbc", WebPush.b64u(as_key.private_key_bytes), WebPush.b64u(as_key.public_key_bytes), "mailto:cook@example.com", 1_735_689_600)
  assert auth.start_with?("vapid t=")
  jwt = auth.split("t=")[1].split(",")[0]
  header, claims, sig = jwt.split(".")
  assert_equal %({"aud":"https://web.push.apple.com","exp":1735732800,"sub":"mailto:cook@example.com"}), WebPush.unb64u(claims)
  assert OpenSSL::PKey::EC.from_public_bytes("prime256v1", as_key.public_key_bytes).verify_raw("SHA256", WebPush.unb64u(sig), "#{header}.#{claims}")
  assert_equal WebPush.b64u(as_key.public_key_bytes), auth.split("k=")[1]
end

test "the app mints one VAPID keypair and serves the public half" do
  get "/push/key"
  assert_equal 200, status
  assert_equal 87, body.size
  assert body.start_with?("B")
  key = body
  get "/push/key"
  assert_equal key, body
end

test "a device can subscribe, is listed, gets a test, and can be removed" do
  post "/push/subscribe", endpoint: "not a url", p256dh: "x", auth: "y", label: "Phone"
  assert_equal 400, status
  # An endpoint nothing listens on: the send fails cleanly and the subscription is kept for next time.
  post "/push/subscribe", endpoint: "https://127.0.0.1:9/push/abc", p256dh: "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4", auth: "BTBZMqHH6r4Tts7J_aSIgg", label: "iPhone Safari"
  assert_equal 200, status
  get "/"
  assert body.include?("iPhone Safari")
  assert body.include?("never sent")
  post "/push/test"
  assert_equal 303, status
  assert header("Location").to_s.include?("did+not+accept") || header("Location").to_s.include?("did%20not%20accept")
  get "/"
  assert body.include?("last send failed")
  post "/push/unsubscribe", endpoint: "https://127.0.0.1:9/push/abc"
  get "/"
  assert !body.include?("iPhone Safari")
end

test "a plan from the roast preset has its dishes and a timeline" do
  post "/plans", name: "Sunday roast", date: "2026-09-20", time: "18:00", tz: TZ.to_s, preset: "roast"
  assert_equal 303, status
  id = redirect_token
  get "/plans/#{id}"
  assert_equal 200, status
  assert body.include?("Yorkshire puddings")
  assert body.include?("Serving <strong>Sun 20 Sep at 18:00</strong>")
  get "/plans/#{id}/cook"
  assert_equal 200, status
  assert body.include?("Dinner is served")
  assert body.include?("Roast the beef")
  assert_equal 5, object(Plan, id).dishes.size
  assert_equal 15, object(Plan, id).timeline.size
end

test "steps can be added, edited, reordered between dishes, ticked off and deleted" do
  post "/plans", name: "Test", date: "2026-09-20", time: "19:00", tz: TZ.to_s, preset: ""
  plan_id = redirect_token
  post "/plans/#{plan_id}/dishes", name: "Chicken"
  chicken = header("Location").to_s.split("dish-").last
  post "/plans/#{plan_id}/dishes", name: "Salad"
  salad = header("Location").to_s.split("dish-").last
  post "/plans/#{plan_id}/dishes/#{chicken}/steps", name: "Roast", minutes: "60", place: "oven2", hands: "0"
  assert_equal 303, status
  post "/plans/#{plan_id}/dishes/#{salad}/steps", name: "Toss", minutes: "5", place: "", hands: "1"
  get "/plans/#{plan_id}/cook"
  assert body.include?("Oven 2")
  assert body.include?("18:00")

  step_ids = body.scan(/data-step="(\d+)"/).flatten
  assert_equal 2, step_ids.size
  roast, toss = step_ids
  post "/plans/#{plan_id}/steps/#{roast}", name: "Roast the chicken", minutes: "75", place: "oven1", hands: "0"
  post "/plans/#{plan_id}/reorder", dishes: "#{salad},#{chicken}", order: "#{toss}:#{chicken},#{roast}:#{chicken}"
  assert_equal 200, status
  get "/plans/#{plan_id}/cook"
  assert body.include?("Roast the chicken")
  assert body.include?("17:40")
  assert body.include?("Toss</span>")
  assert_equal "Salad", object(Plan, plan_id).dishes.first["name"]

  post "/plans/#{plan_id}/steps/#{toss}/done", done: "1"
  assert_equal "done", body
  get "/plans/#{plan_id}/cook"
  assert body.include?("checked")
  post "/plans/#{plan_id}/reset"
  get "/plans/#{plan_id}/cook"
  assert !body.include?("checked")

  post "/plans/#{plan_id}/steps/#{roast}/delete"
  get "/plans/#{plan_id}"
  assert !body.include?("Roast the chicken")
end

test "serving time can be shifted and a plan copied and deleted" do
  post "/plans", name: "Shifty", date: "2026-09-20", time: "18:00", tz: TZ.to_s, preset: "roast"
  id = redirect_token
  post "/plans/#{id}/shift", minutes: "15"
  get "/plans/#{id}/cook"
  assert body.include?("18:15")
  post "/plans/#{id}/duplicate"
  copy = redirect_token
  assert copy != id
  get "/plans/#{copy}"
  assert body.include?("Shifty (copy)")
  assert body.include?("Sun 27 Sep")
  assert_equal 15, object(Plan, copy).steps.size
  post "/plans/#{id}/delete"
  get "/plans/#{id}"
  assert_equal 404, status
  assert !Plan.exists?(id)
end

test "a step that is due right now fires the timer and records an alert" do
  serve = (Time.now.to_i / 60) * 60 + 600
  post "/plans", name: "Quick", date: Clock.ymd(serve, 0), time: Clock.hhmm(serve, 0), tz: "0", preset: ""
  id = redirect_token
  post "/plans/#{id}/dishes", name: "Toast"
  dish = header("Location").to_s.split("dish-").last
  post "/plans/#{id}/dishes/#{dish}/steps", name: "Put the bread in", minutes: "10", place: "", hands: "0"
  assert fire_timer(Plan, id)
  alert = object(Plan, id).last_alert.to_s
  assert alert.include?("Now: Put the bread in"), alert
  assert alert.include?("Toast · until #{Clock.hhmm(serve, 0)}"), alert
  assert_equal 1, object(Plan, id).timeline.size
  assert !object(Plan, id).timeline.first["alerted_at"].nil?
end

test "a due step is pushed to every subscribed device from the worker" do
  post "/push/subscribe", endpoint: "https://127.0.0.1:9/push/worker", p256dh: "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4", auth: "BTBZMqHH6r4Tts7J_aSIgg", label: "Test device"
  serve = (Time.now.to_i / 60) * 60 + 300
  post "/plans", name: "Pushy", date: Clock.ymd(serve, 0), time: Clock.hhmm(serve, 0), tz: "0", preset: ""
  id = redirect_token
  post "/plans/#{id}/dishes", name: "Tea"
  dish = header("Location").to_s.split("dish-").last
  post "/plans/#{id}/dishes/#{dish}/steps", name: "Boil the kettle", minutes: "5", place: "", hands: "0"
  assert fire_timer(Plan, id)
  assert object(Plan, id).last_alert.to_s.include?("Boil the kettle")
  get "/"
  assert body.include?("Test device")
  assert body.include?("last send failed")
  post "/push/unsubscribe", endpoint: "https://127.0.0.1:9/push/worker"
end

test "a finished timer rides along with the step that starts as it ends" do
  serve = (Time.now.to_i / 60) * 60 + 600
  post "/plans", name: "Chain", date: Clock.ymd(serve, 0), time: Clock.hhmm(serve, 0), tz: "0", preset: ""
  id = redirect_token
  post "/plans/#{id}/dishes", name: "Beef"
  dish = header("Location").to_s.split("dish-").last
  post "/plans/#{id}/dishes/#{dish}/steps", name: "Roast", minutes: "10", place: "oven1", hands: "0"
  post "/plans/#{id}/dishes/#{dish}/steps", name: "Rest", minutes: "10", place: "", hands: "0"
  # The roast ends exactly where the rest begins, so one alert carries both.
  fire_timer(Plan, id)
  alert = object(Plan, id).last_alert.to_s
  assert alert.include?("Now: Rest"), alert
  assert alert.include?("Roast is done — Beef · out of Oven 1"), alert
end

test "a hands-on step is not a timer, so it never reports itself done" do
  serve = (Time.now.to_i / 60) * 60 + 600
  post "/plans", name: "Hands", date: Clock.ymd(serve, 0), time: Clock.hhmm(serve, 0), tz: "0", preset: ""
  id = redirect_token
  post "/plans/#{id}/dishes", name: "Veg"
  dish = header("Location").to_s.split("dish-").last
  post "/plans/#{id}/dishes/#{dish}/steps", name: "Chop", minutes: "10", place: "", hands: "1"
  post "/plans/#{id}/dishes/#{dish}/steps", name: "Steam", minutes: "10", place: "hob", hands: "0"
  fire_timer(Plan, id)
  alert = object(Plan, id).last_alert.to_s
  assert alert.include?("Now: Steam"), alert
  assert !alert.include?("Chop is done"), alert
end

test "a step in the future arms the timer for its start and does not alert yet" do
  serve = Time.now.to_i + 7200
  post "/plans", name: "Later", date: Clock.ymd(serve, 0), time: Clock.hhmm(serve, 0), tz: "0", preset: ""
  id = redirect_token
  post "/plans/#{id}/dishes", name: "Soup"
  dish = header("Location").to_s.split("dish-").last
  post "/plans/#{id}/dishes/#{dish}/steps", name: "Heat the soup", minutes: "20", place: "hob", hands: "0"
  assert fire_timer(Plan, id)
  assert_equal nil, object(Plan, id).last_alert
end

test "a plan typed in late does not alert for steps already long past" do
  serve = Time.now.to_i + 600
  post "/plans", name: "Late", date: Clock.ymd(serve, 0), time: Clock.hhmm(serve, 0), tz: "0", preset: ""
  id = redirect_token
  post "/plans/#{id}/dishes", name: "Beef"
  dish = header("Location").to_s.split("dish-").last
  post "/plans/#{id}/dishes/#{dish}/steps", name: "Roast", minutes: "90", place: "oven1", hands: "0"
  fire_timer(Plan, id)
  assert_equal nil, object(Plan, id).last_alert
  assert !object(Plan, id).timeline.first["alerted_at"].nil?
end

test "bad input is refused" do
  post "/plans", name: "x", date: "soon", time: "18:00", tz: "0", preset: ""
  assert_equal 400, status
  get "/plans/999999"
  assert_equal 404, status
  assert body.include?("Not here")
end

# ---- passkeys ----
#
# The harness has no browser, so these build the bytes an authenticator would send and check that the
# verification either accepts them or names the reason it will not. The signing key stands in for the one
# living in a Secure Enclave; everything else is the real wire format.

RP = "dinner.example"
ORIGIN = "https://dinner.example"
# A P-256 SubjectPublicKeyInfo is this fixed 26-byte preamble followed by the uncompressed point.
SPKI_HEAD = ["3059301306072a8648ce3d020106082a8648ce3d030107034200"].pack("H*")

def spki_for(key) = SPKI_HEAD + key.public_key_bytes

def authenticator_data(rp_id, flags, count)
  OpenSSL::Digest::SHA256.digest(rp_id) + flags.chr + [count].pack("N")
end

def client_data(type, challenge, origin)
  %({"type":"#{type}","challenge":"#{challenge}","origin":"#{origin}","crossOrigin":false})
end

# The inverse of WebAuthn.raw_signature: what a browser actually puts on the wire.
def der_signature(raw)
  halves = [raw.byteslice(0, 32), raw.byteslice(32, 32)].map do |half|
    from = 0
    from += 1 while from < half.bytesize - 1 && half.getbyte(from).zero?
    trimmed = half.byteslice(from, half.bytesize - from)
    trimmed.getbyte(0) >= 0x80 ? "\x00" + trimmed : trimmed
  end
  body = halves.map { |h| "\x02" + h.bytesize.chr + h }.join
  "\x30" + body.bytesize.chr + body
end

def signed_assertion(key, rp_id, challenge, origin, count)
  auth = authenticator_data(rp_id, 0x05, count)
  client = client_data("webauthn.get", challenge, origin)
  raw = key.sign_raw("SHA256", auth + OpenSSL::Digest::SHA256.digest(client))
  { "auth" => B64.encode(auth), "client" => B64.encode(client), "sig" => B64.encode(der_signature(raw)) }
end

test "a registration is accepted, and the key is stored in the shape the login will need" do
  key = OpenSSL::PKey::EC.generate("prime256v1")
  challenge = WebAuthn.challenge
  result = WebAuthn.verify_registration(RP, ORIGIN, challenge,
                                        B64.encode(client_data("webauthn.create", challenge, ORIGIN)),
                                        B64.encode(authenticator_data(RP, 0x45, 0)),
                                        B64.encode(spki_for(key)))
  assert result["ok"], result["error"].to_s
  assert_equal B64.encode(key.public_key_bytes), result["public_key"]
  assert_equal 0, result["sign_count"]
end

test "a login signed by that key is accepted, and a DER signature survives the trip to raw r||s" do
  key = OpenSSL::PKey::EC.generate("prime256v1")
  challenge = WebAuthn.challenge
  a = signed_assertion(key, RP, challenge, ORIGIN, 7)
  result = WebAuthn.verify_assertion(RP, ORIGIN, challenge, a["client"], a["auth"], a["sig"],
                                     B64.encode(key.public_key_bytes), 3)
  assert result["ok"], result["error"].to_s
  assert_equal 7, result["sign_count"]
end

test "signatures are checked over enough runs to catch a mangled half" do
  # A DER integer drops leading zero bytes, so about one signature in 256 has a short half and one in 256
  # carries an extra 0x00. Both shapes have to survive, which one run would not reliably show.
  key = OpenSSL::PKey::EC.generate("prime256v1")
  ok = 0
  20.times do
    challenge = WebAuthn.challenge
    a = signed_assertion(key, RP, challenge, ORIGIN, 0)
    ok += 1 if WebAuthn.verify_assertion(RP, ORIGIN, challenge, a["client"], a["auth"], a["sig"],
                                         B64.encode(key.public_key_bytes), 0)["ok"]
  end
  assert_equal 20, ok
end

test "a login is refused when the ceremony was not this one" do
  key = OpenSSL::PKey::EC.generate("prime256v1")
  challenge = WebAuthn.challenge
  good = B64.encode(key.public_key_bytes)

  # another site relaying a ceremony here
  a = signed_assertion(key, RP, challenge, "https://evil.example", 0)
  assert_equal "that ceremony came from another site",
               WebAuthn.verify_assertion(RP, ORIGIN, challenge, a["client"], a["auth"], a["sig"], good, 0)["error"]

  # a challenge this app never issued
  a = signed_assertion(key, RP, WebAuthn.challenge, ORIGIN, 0)
  assert_equal "that challenge is not the one this app issued",
               WebAuthn.verify_assertion(RP, ORIGIN, challenge, a["client"], a["auth"], a["sig"], good, 0)["error"]

  # a passkey made for a different hostname
  a = signed_assertion(key, "other.example", challenge, ORIGIN, 0)
  assert_equal "that passkey belongs to another site",
               WebAuthn.verify_assertion(RP, ORIGIN, challenge, a["client"], a["auth"], a["sig"], good, 0)["error"]

  # somebody else's key
  other = OpenSSL::PKey::EC.generate("prime256v1")
  a = signed_assertion(other, RP, challenge, ORIGIN, 0)
  assert_equal "that signature does not match this passkey",
               WebAuthn.verify_assertion(RP, ORIGIN, challenge, a["client"], a["auth"], a["sig"], good, 0)["error"]

  # a registration ceremony replayed as a login
  client = B64.encode(client_data("webauthn.create", challenge, ORIGIN))
  a = signed_assertion(key, RP, challenge, ORIGIN, 0)
  assert_equal "that was the wrong kind of ceremony",
               WebAuthn.verify_assertion(RP, ORIGIN, challenge, client, a["auth"], a["sig"], good, 0)["error"]
end

test "a counter that has not moved is a copied passkey, but only when both sides keep one" do
  key = OpenSSL::PKey::EC.generate("prime256v1")
  good = B64.encode(key.public_key_bytes)
  challenge = WebAuthn.challenge
  a = signed_assertion(key, RP, challenge, ORIGIN, 4)
  assert_equal "that passkey looks like a copy",
               WebAuthn.verify_assertion(RP, ORIGIN, challenge, a["client"], a["auth"], a["sig"], good, 9)["error"]
  # Apple and Google authenticators always send zero; that is not evidence of anything.
  a = signed_assertion(key, RP, challenge, ORIGIN, 0)
  assert WebAuthn.verify_assertion(RP, ORIGIN, challenge, a["client"], a["auth"], a["sig"], good, 0)["ok"]
end

test "nothing malformed gets through, and nothing malformed raises" do
  key = OpenSSL::PKey::EC.generate("prime256v1")
  good = B64.encode(key.public_key_bytes)
  challenge = WebAuthn.challenge
  a = signed_assertion(key, RP, challenge, ORIGIN, 0)
  ["", "!!!not base64!!!", B64.encode("short")].each do |junk|
    assert !WebAuthn.verify_assertion(RP, ORIGIN, challenge, junk, a["auth"], a["sig"], good, 0)["ok"]
    assert !WebAuthn.verify_assertion(RP, ORIGIN, challenge, a["client"], junk, a["sig"], good, 0)["ok"]
    assert !WebAuthn.verify_assertion(RP, ORIGIN, challenge, a["client"], a["auth"], junk, good, 0)["ok"]
  end
  assert_equal "", WebAuthn.raw_signature("")
  assert_equal "", WebAuthn.raw_signature("\x30\x06\x02\x01\x01")
  assert_equal "", WebAuthn.public_key_point("")
  assert_equal "", WebAuthn.public_key_point(SPKI_HEAD + ("\x09" * 65))
end

test "a passkey is the only way in, and the first one needs the setup secret" do
  post "/auth/logout"
  get "/plans/1"
  assert_equal 303, status
  assert_equal "/login", header("Location")
  get "/"
  assert_equal 303, status

  get "/login"
  assert_equal 200, status
  assert body.include?("Sign in with a passkey")

  # Enrolling is not open just because the page that starts it is.
  post "/auth/register/options"
  assert_equal 403, status
  # And setup is a one-time door: it closed the moment the first account existed.
  post "/auth/setup", secret: ENV.fetch("SETUP_SECRET", ""), name: "Someone else"
  assert_equal 404, status

  sign_in_with_passkey
  assert_equal 200, status
  get "/"
  assert_equal 200, status
  assert body.include?("Test device")
end

test "the registration options ask for the kind of passkey that names its own owner" do
  post "/auth/register/options"
  assert_equal 200, status
  options = JSON.parse(body)
  assert_equal "required", options["authenticatorSelection"]["residentKey"]
  assert_equal(-7, options["pubKeyCredParams"].first["alg"])
  assert_equal TEST_RP, options["rp"]["id"]
  assert_equal 22, options["user"]["id"].size
  assert_equal 43, options["challenge"].size
  # The passkey already enrolled is excluded, so the same device cannot register twice.
  assert_equal [TEST_CREDENTIAL], options["excludeCredentials"].map { |c| c["id"] }
end

test "a login is refused when the assertion is not this app's" do
  post "/auth/logout"
  get "/login" # signing out clears the session, and with it the CSRF token the next post needs
  post "/auth/login/options"
  challenge = JSON.parse(body)["challenge"]
  a = signed_assertion(TEST_KEY, TEST_RP, challenge, "https://evil.example", 0)
  post "/auth/login", credential_id: TEST_CREDENTIAL, client_data: a["client"],
                      authenticator_data: a["auth"], signature: a["sig"], user_handle: ""
  assert_equal 403, status
  get "/"
  assert_equal 303, status

  # An unknown credential is refused before anything is verified.
  post "/auth/login/options"
  a = signed_assertion(TEST_KEY, TEST_RP, JSON.parse(body)["challenge"], TEST_ORIGIN, 0)
  post "/auth/login", credential_id: B64.encode("nobody"), client_data: a["client"],
                      authenticator_data: a["auth"], signature: a["sig"], user_handle: ""
  assert_equal 403, status
end
