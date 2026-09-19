# frozen_string_literal: true
# `melee test` runs this under CRuby; `melee test --spinel` runs it against the compiled binary.
require_relative "../lib/clock"
require_relative "../lib/schedule"
require_relative "../lib/web_push"

# GET /push/key answers with the VAPID public key, minted per database, so the two runtimes' transcripts would
# never agree on that body without masking its shape.
mask(/\AB[A-Za-z0-9_-]{86}\z/)

TZ = -60 # British Summer Time, as a browser reports it

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
