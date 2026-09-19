# frozen_string_literal: true
require_relative "lib/clock"
require_relative "lib/schedule"
require_relative "lib/presets"
require_relative "lib/alerts"
require_relative "lib/plan"

title "Dinner Time"

PLACES = %w[oven1 oven2 hob].freeze

get "/" do
  plans = db.query("SELECT id, name, serve_at, tz_offset FROM plans ORDER BY serve_at DESC, id DESC")
  render :index, plans: plans, devices: Alerts.subscriptions, notice: params.fetch(:notice)
end

# The VAPID public key the browser subscribes with. Fetched when needed rather than carried on every page.
get "/push/key" do
  text WebPush.public_key
end

post "/push/subscribe" do
  endpoint = params.fetch(:endpoint).strip
  halt 400, "That is not a push endpoint" unless endpoint.match?(%r{\Ahttps://[^\s]+\z})
  halt 400, "Missing keys" if params.fetch(:p256dh).empty? || params.fetch(:auth).empty?
  Alerts.subscribe(endpoint, params.fetch(:p256dh), params.fetch(:auth), params.fetch(:label).strip[0, 80])
  text Alerts.count.to_s
end

post "/push/unsubscribe" do
  Alerts.unsubscribe(params.fetch(:endpoint))
  redirect "/"
end

post "/push/test" do
  halt 400, "No device has asked for alerts yet" if Alerts.count.zero?
  sent = Alerts.broadcast("Dinner Time test", "If you can read this, alerts will reach this device.", "/", "test")
  redirect "/?notice=#{url_encode(sent.zero? ? "The push service did not accept it. Check the log." : "Sent to #{sent} device#{sent == 1 ? "" : "s"}.")}"
end

post "/plans" do
  tz = params.fetch(:tz).to_i
  serve_at = Clock.parse(params.fetch(:date), params.fetch(:time), tz)
  halt 400, "Pick a date and a time" if serve_at.nil?
  name = params.fetch(:name).strip
  name = "Dinner" if name.empty?
  db.run "INSERT INTO plans (name, serve_at, tz_offset, created_at) VALUES (?, ?, ?, ?)", name, serve_at, tz, Time.now.to_i
  plan_id = db.last_id
  plan = Plan.get(plan_id.to_s)
  seed(plan, params.fetch(:preset))
  plan.configure(name, serve_at, tz)
  redirect "/plans/#{plan_id}"
end

get "/plans/:id" do
  plan = plan!
  obj = object_for(plan)
  render :plan, plan: plan, dishes: obj.dishes, steps: obj.steps, title: plan["name"].to_s
end

get "/plans/:id/cook" do
  plan = plan!
  render :cook, plan: plan, placed: object_for(plan).timeline, devices: Alerts.count, last_alert: object_for(plan).last_alert.to_s, title: plan["name"].to_s, board: true
end

post "/plans/:id" do
  plan = plan!
  tz = params.fetch(:tz, plan["tz_offset"].to_s).to_i
  serve_at = Clock.parse(params.fetch(:date), params.fetch(:time), tz)
  halt 400, "Pick a date and a time" if serve_at.nil?
  name = params.fetch(:name).strip
  name = plan["name"].to_s if name.empty?
  db.run "UPDATE plans SET name = ?, serve_at = ?, tz_offset = ? WHERE id = ?", name, serve_at, tz, plan["id"]
  object_for(plan).configure(name, serve_at, tz)
  redirect back
end

post "/plans/:id/shift" do
  plan = plan!
  minutes = params.fetch(:minutes).to_i
  halt 400, "Shift between -180 and 180 minutes" unless minutes.between?(-180, 180)
  serve_at = object_for(plan).shift_serve(minutes)
  db.run "UPDATE plans SET serve_at = ? WHERE id = ?", serve_at, plan["id"]
  redirect "/plans/#{plan["id"]}/cook"
end

post "/plans/:id/reset" do
  plan = plan!
  object_for(plan).reset_done
  redirect "/plans/#{plan["id"]}/cook"
end

post "/plans/:id/duplicate" do
  plan = plan!
  name = "#{plan["name"]} (copy)"
  serve_at = plan["serve_at"].to_i + 7 * Clock::DAY
  db.run "INSERT INTO plans (name, serve_at, tz_offset, created_at) VALUES (?, ?, ?, ?)", name, serve_at, plan["tz_offset"], Time.now.to_i
  copy_id = db.last_id
  copy = Plan.get(copy_id.to_s)
  copy.import(object_for(plan).export)
  copy.configure(name, serve_at, plan["tz_offset"].to_i)
  redirect "/plans/#{copy_id}"
end

post "/plans/:id/delete" do
  plan = plan!
  object_for(plan).remove
  db.run "DELETE FROM plans WHERE id = ?", plan["id"]
  redirect "/"
end

post "/plans/:id/dishes" do
  plan = plan!
  name = params.fetch(:name).strip
  halt 400, "A dish needs a name" if name.empty?
  dish_id = object_for(plan).add_dish(name)
  redirect "/plans/#{plan["id"]}#dish-#{dish_id}"
end

# order: "stepId:dishId,stepId:dishId,..." in the order shown; dishes: "dishId,dishId,..."
post "/plans/:id/reorder" do
  plan = plan!
  dish_ids = params.fetch(:dishes).split(",").map(&:to_i)
  object_for(plan).reorder(dish_ids, params.fetch(:order).split(","))
  text "ok"
end

post "/plans/:id/dishes/:dish" do
  plan = plan!
  name = params.fetch(:name).strip
  object_for(plan).rename_dish(dish_id, name) unless name.empty?
  redirect "/plans/#{plan["id"]}#dish-#{dish_id}"
end

post "/plans/:id/dishes/:dish/move" do
  plan = plan!
  object_for(plan).move_dish(dish_id, params.fetch(:dir) == "up")
  redirect "/plans/#{plan["id"]}#dish-#{dish_id}"
end

post "/plans/:id/dishes/:dish/delete" do
  plan = plan!
  object_for(plan).delete_dish(dish_id)
  redirect "/plans/#{plan["id"]}"
end

post "/plans/:id/dishes/:dish/steps" do
  plan = plan!
  f = step_fields
  object_for(plan).add_step(dish_id, f["name"], f["minutes"], f["place"], f["hands"])
  redirect "/plans/#{plan["id"]}#dish-#{dish_id}"
end

post "/plans/:id/steps/:step" do
  plan = plan!
  f = step_fields
  object_for(plan).update_step(step_id, f["name"], f["minutes"], f["place"], f["hands"])
  redirect "/plans/#{plan["id"]}#step-#{step_id}"
end

post "/plans/:id/steps/:step/delete" do
  plan = plan!
  object_for(plan).delete_step(step_id)
  redirect "/plans/#{plan["id"]}"
end

post "/plans/:id/steps/:step/done" do
  plan = plan!
  text object_for(plan).set_done(step_id, params.fetch(:done) == "1")
end

not_found do
  render :missing, title: "Not here"
end

def plan!
  plan = db.first("SELECT id, name, serve_at, tz_offset FROM plans WHERE id = ?", request.path_params.fetch("id").to_i)
  halt 404 if plan.nil?
  plan
end

def object_for(plan) = Plan.get(plan["id"].to_s)
def dish_id = params.fetch(:dish).to_i
def step_id = params.fetch(:step).to_i

# The fields of a step form, validated.
def step_fields
  name = params.fetch(:name).strip
  halt 400, "A step needs a name" if name.empty?
  minutes = params.fetch(:minutes).to_i
  halt 400, "Minutes must be between 0 and 1440" unless minutes.between?(0, 1440)
  place = params.fetch(:place)
  place = "" unless PLACES.include?(place)
  { "name" => name, "minutes" => minutes, "place" => place, "hands" => params.fetch(:hands) == "1" ? 1 : 0 }
end

def seed(plan, preset)
  dish_ids = {}
  Presets.lines(preset).each do |line|
    dish, name, minutes, place, hands = line.split("|", -1)
    dish_ids[dish] = plan.add_dish(dish) unless dish_ids.key?(dish)
    plan.add_step(dish_ids[dish], name, minutes.to_i, place, hands.to_i)
  end
end

def place_label(place) = Plan.place_name(place)

def hhmm(secs, plan) = Clock.hhmm(secs.to_i, plan["tz_offset"].to_i)
def day_label(plan) = Clock.day_label(plan["serve_at"].to_i, plan["tz_offset"].to_i)
def serve_ymd(plan) = Clock.ymd(plan["serve_at"].to_i, plan["tz_offset"].to_i)
