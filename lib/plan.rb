# frozen_string_literal: true
# One dinner, as a durable object: its dishes, their chains of steps, what has been ticked off, and the timer
# that fires when the next step is due. The object holds the plan and works out the timeline; the routes turn
# that into pages. Alerts go out from `on_timer` in the worker, so they fire with the phone in a pocket.
require_relative "schedule"
require_relative "clock"
require_relative "alerts"

class Plan < Durable
  GRACE = 90 # seconds a step may already be overdue and still get its alert when the plan is (re)armed

  def self.place_name(place)
    case place
    when "oven1" then "Oven 1"
    when "oven2" then "Oven 2"
    when "hob" then "Hob"
    else ""
    end
  end

  def configure(name, serve_at, tz_offset)
    storage.put("name", name.to_s)
    storage.put("serve_at", serve_at.to_i)
    storage.put("tz_offset", tz_offset.to_i)
    arm
  end

  def info
    { "name" => storage.get("name").to_s, "serve_at" => storage.get("serve_at").to_i, "tz_offset" => storage.get("tz_offset").to_i }
  end

  def dishes = storage.query("SELECT id, name, position FROM dishes ORDER BY position, id")

  def steps
    storage.query "SELECT s.id, s.dish_id, s.name, s.minutes, s.place, s.hands, s.position, s.done_at, s.started_at, s.alerted_at, s.end_alerted_at " \
                  "FROM steps s JOIN dishes d ON d.id = s.dish_id ORDER BY d.position, s.position, s.id"
  end

  def timeline = Schedule.compute(serve_at, dishes, steps)

  def add_dish(name)
    storage.run "INSERT INTO dishes (name, position) VALUES (?, ?)", name.to_s, after(storage.first("SELECT MAX(position) AS m FROM dishes"))
    id = storage.last_id
    arm
    id
  end

  def rename_dish(dish_id, name)
    storage.run "UPDATE dishes SET name = ? WHERE id = ?", name.to_s, dish_id.to_i
    nil
  end

  def move_dish(dish_id, up)
    ids = dishes.map { |d| d["id"].to_i }
    at = ids.index(dish_id.to_i)
    return nil if at.nil?
    to = up ? at - 1 : at + 1
    return nil unless to.between?(0, ids.size - 1)
    ids[at], ids[to] = ids[to], ids[at]
    storage.transaction do
      ids.each_with_index { |id, i| storage.run "UPDATE dishes SET position = ? WHERE id = ?", i, id }
    end
    arm
  end

  def delete_dish(dish_id)
    storage.run "DELETE FROM dishes WHERE id = ?", dish_id.to_i
    arm
  end

  def add_step(dish_id, name, minutes, place, hands)
    storage.run "INSERT INTO steps (dish_id, name, minutes, place, hands, position) VALUES (?, ?, ?, ?, ?, ?)",
                dish_id.to_i, name.to_s, minutes.to_i, place.to_s, hands.to_i,
                after(storage.first("SELECT MAX(position) AS m FROM steps WHERE dish_id = ?", dish_id.to_i))
    id = storage.last_id
    arm
    id
  end

  def update_step(step_id, name, minutes, place, hands)
    storage.run "UPDATE steps SET name = ?, minutes = ?, place = ?, hands = ? WHERE id = ?", name.to_s, minutes.to_i, place.to_s, hands.to_i, step_id.to_i
    arm
  end

  def delete_step(step_id)
    storage.run "DELETE FROM steps WHERE id = ?", step_id.to_i
    arm
  end

  # dish_ids: every dish id in its new order. pairs: "stepId:dishId" for every step, in the order shown.
  def reorder(dish_ids, pairs)
    known = dishes.map { |d| d["id"].to_i }
    storage.transaction do
      dish_ids.each_with_index do |id, i|
        storage.run "UPDATE dishes SET position = ? WHERE id = ?", i, id.to_i if known.include?(id.to_i)
      end
      pairs.each_with_index do |pair, i|
        step_id, dish_id = pair.to_s.split(":").map(&:to_i)
        storage.run "UPDATE steps SET dish_id = ?, position = ? WHERE id = ?", dish_id, i, step_id if known.include?(dish_id)
      end
    end
    arm
  end

  def set_done(step_id, done)
    storage.run "UPDATE steps SET done_at = ? WHERE id = ?", done ? Time.now.to_i : nil, step_id.to_i
    arm
    done ? "done" : "undone"
  end

  # Starting is its own event. A cook who says "it is in the oven" is not saying "it is cooked", and until
  # this was recordable the only control meant the second thing.
  def set_started(step_id, started)
    storage.run "UPDATE steps SET started_at = ?, done_at = NULL WHERE id = ?", started ? Time.now.to_i : nil, step_id.to_i
    arm
    started ? "started" : "unstarted"
  end

  def reset_done
    storage.run "UPDATE steps SET done_at = NULL, started_at = NULL, alerted_at = NULL, end_alerted_at = NULL"
    storage.delete("served_alerted")
    arm
  end

  def shift_serve(minutes)
    storage.put("serve_at", serve_at + minutes.to_i * 60)
    arm
    serve_at
  end

  # The dishes and steps without their progress, for copying into another plan.
  def export
    { "dishes" => dishes,
      "steps" => storage.query("SELECT id, dish_id, name, minutes, place, hands, position FROM steps ORDER BY position, id") }
  end

  def import(data)
    ids = {}
    storage.transaction do
      data["dishes"].each do |d|
        storage.run "INSERT INTO dishes (name, position) VALUES (?, ?)", d["name"].to_s, d["position"].to_i
        ids[d["id"].to_i] = storage.last_id
      end
      data["steps"].each do |s|
        dish = ids[s["dish_id"].to_i]
        next if dish.nil?
        storage.run "INSERT INTO steps (dish_id, name, minutes, place, hands, position) VALUES (?, ?, ?, ?, ?, ?)",
                    dish, s["name"].to_s, s["minutes"].to_i, s["place"].to_s, s["hands"].to_i, s["position"].to_i
      end
    end
    arm
  end

  def last_alert = storage.get("last_alert")

  def remove
    destroy
    nil
  end

  # The timer fires at the start of the next step nobody has been told about yet, or at serving time.
  # Steps in a dish are butt-joined: one ends exactly where the next begins. So a finished timer usually has a
  # start to ride along with, and only stands alone at the end of a chain or across a gap a clash opened up.
  def on_timer
    now = Time.now.to_i
    plan = timeline
    due = plan.select { |s| s["done_at"].nil? && s["alerted_at"].nil? && s["start_at"].to_i <= now + 2 }
    finished = plan.select { |s| s["done_at"].nil? && s["end_alerted_at"].nil? && timer_step?(s) && Plan.real_end(s) <= now + 2 }
    if !due.empty?
      send_alert(start_text(due, finished, now))
    elsif !finished.empty?
      send_alert(finish_text(finished))
    end
    due.each { |s| storage.run "UPDATE steps SET alerted_at = ? WHERE id = ?", now, s["id"].to_i }
    finished.each { |s| storage.run "UPDATE steps SET end_alerted_at = ? WHERE id = ?", now, s["id"].to_i }
    if storage.get("served_alerted").nil? && serve_at <= now + 2
      send_alert("Dinner is served\n#{storage.get("name")}: everything should be on the table.")
      storage.put("served_alerted", now)
    end
    arm
  end

  private

  def serve_at = storage.get("serve_at").to_i
  def tz = storage.get("tz_offset").to_i

  def after(row) = row.nil? || row["m"].nil? ? 0 : row["m"].to_i + 1

  # Work out when the timer should next fire. A step that slipped into the past because the plan was edited or
  # serving time moved earlier is marked as handled without an alert — nobody wants ten notifications for a
  # plan they typed in late — unless it is only just overdue, in which case it fires straight away. A step
  # that moved back into the future gets a fresh alert when its time comes round again.
  def arm
    now = Time.now.to_i
    soonest = nil
    fire_now = false
    timeline.each do |s|
      next unless s["done_at"].nil?
      start = s["start_at"].to_i
      alerted = !s["alerted_at"].nil?
      if alerted && start > now + GRACE
        storage.run "UPDATE steps SET alerted_at = NULL WHERE id = ?", s["id"].to_i
        alerted = false
      end
      unless alerted
        if start < now - GRACE
          storage.run "UPDATE steps SET alerted_at = ? WHERE id = ?", now, s["id"].to_i
        elsif start <= now
          fire_now = true
        elsif soonest.nil? || start < soonest
          soonest = start
        end
      end
      next unless timer_step?(s)
      finish = Plan.real_end(s)
      ended = !s["end_alerted_at"].nil?
      if ended && finish > now + GRACE
        storage.run "UPDATE steps SET end_alerted_at = NULL WHERE id = ?", s["id"].to_i
        ended = false
      end
      next if ended
      if finish < now - GRACE
        storage.run "UPDATE steps SET end_alerted_at = ? WHERE id = ?", now, s["id"].to_i
      elsif finish <= now
        fire_now = true
      elsif soonest.nil? || finish < soonest
        soonest = finish
      end
    end
    storage.delete("served_alerted") if !storage.get("served_alerted").nil? && serve_at > now + GRACE
    if storage.get("served_alerted").nil?
      if serve_at < now - GRACE then storage.put("served_alerted", now)
      elsif serve_at <= now then fire_now = true
      elsif soonest.nil? || serve_at < soonest then soonest = serve_at
      end
    end
    if fire_now then timer(after: 0)
    elsif soonest.nil? then cancel_timer
    else timer(at: soonest)
    end
    nil
  end

  # A step you have to stand over occupies the cook; anything else is a timer they can walk away from.
  def timer_step?(step) = step["hands"].to_i.zero? && step["end_at"].to_i > step["start_at"].to_i

  # What the clock on the wall says this step will finish, which is the plan's time only until it begins.
  def self.real_end(step)
    return step["end_at"].to_i if step["started_at"].nil?
    step["started_at"].to_i + step["minutes"].to_i * 60
  end

  def where_of(step) = step["place"].to_s.empty? ? "" : Plan.place_name(step["place"].to_s)

  def start_text(due, finished, now)
    lines = due.map do |s|
      where = where_of(s).empty? ? "" : " · #{where_of(s)}"
      ends = s["end_at"].to_i > s["start_at"].to_i ? " · until #{Clock.hhmm(s["end_at"].to_i, tz)}" : ""
      late = now - s["start_at"].to_i > GRACE ? " (was #{Clock.hhmm(s["start_at"].to_i, tz)})" : ""
      "#{s["name"]} — #{s["dish"]}#{where}#{ends}#{late}"
    end
    head = due.size == 1 ? "Now: #{due.first["name"]}" : "Now: #{due.size} things"
    ([head] + lines + finished_lines(finished)).join("\n")
  end

  # A timer running out reads differently from a step starting: nothing has to begin, something has finished.
  def finish_text(finished)
    head = finished.size == 1 ? "Timer up: #{finished.first["name"]}" : "#{finished.size} timers up"
    ([head] + finished_lines(finished)).join("\n")
  end

  def finished_lines(finished)
    finished.map do |s|
      out = where_of(s).empty? ? "" : " · out of #{where_of(s)}"
      "#{s["name"]} is done — #{s["dish"]}#{out}"
    end
  end

  # The first line is the headline; the rest is the detail. Every browser that asked for alerts gets a native
  # notification; the text is also kept on the object, which is what the page and the tests read.
  def send_alert(text)
    storage.put("last_alert", text)
    lines = text.split("\n")
    Alerts.broadcast(lines.first.to_s, lines.drop(1).join("\n"), "/plans/#{id}/cook", "plan-#{id}")
    nil
  end
end
