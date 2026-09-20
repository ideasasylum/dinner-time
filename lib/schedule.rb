# frozen_string_literal: true

# Works a plan backwards from the serve time. Each dish is a chain of steps done in order, and the last
# step of every chain ends at the serve time. Only one hands-on step can happen at once, so when two would
# overlap, the one from the dish lower down the list is moved earlier (and everything before it in its
# chain moves with it). Ovens and the hob can hold several things at once, so they only label a step.
module Schedule
  # dishes: rows with "id", "position". steps: rows with "id", "dish_id", "position", "minutes", "hands".
  # Returns one Hash per step, sorted by start time, each with "start_at", "end_at" and "shifted" (1 when
  # a hands-on clash moved it earlier than its chain alone would have).
  def self.compute(serve_at, dishes, steps)
    order = dishes.sort_by { |d| d["position"].to_i }
    chains = order.map { |d| steps.select { |s| s["dish_id"] == d["id"] }.sort_by { |s| s["position"].to_i } }
    names = order.map { |d| d["name"].to_s }
    latest = order.map { |_| serve_at }
    index = chains.map(&:size)
    cursor = nil
    out = []

    loop do
      pick = -1
      chains.each_with_index do |_, i|
        next if index[i].zero?
        pick = i if pick < 0 || latest[i] > latest[pick]
      end
      break if pick < 0

      step = chains[pick][index[pick] - 1]
      wanted = latest[pick]
      hands = step["hands"].to_i == 1
      end_at = hands && !cursor.nil? && cursor < wanted ? cursor : wanted
      start_at = end_at - step["minutes"].to_i * 60
      cursor = start_at if hands
      latest[pick] = start_at
      index[pick] -= 1
      out << placed(step, names[pick], start_at, end_at, end_at < wanted)
    end

    out.sort_by { |s| s["start_at"].to_i * 100 + s["sort"].to_i }
  end

  def self.placed(step, dish, start_at, end_at, shifted)
    {
      "id" => step["id"],
      "dish_id" => step["dish_id"],
      "dish" => dish,
      "name" => step["name"],
      "minutes" => step["minutes"],
      "place" => step["place"],
      "hands" => step["hands"],
      "done_at" => step["done_at"],
      "started_at" => step["started_at"],
      "alerted_at" => step["alerted_at"],
      "end_alerted_at" => step["end_alerted_at"],
      "start_at" => start_at,
      "end_at" => end_at,
      "shifted" => shifted ? 1 : 0,
      "sort" => step["hands"].to_i == 1 ? 0 : 1
    }
  end

  def self.first_start(placed) = placed.empty? ? nil : placed.first["start_at"].to_i

  # How far behind the cook is, in seconds, and nothing fancier: the worst overshoot any unfinished step is
  # already committed to. A step that began late will finish late by the same margin; one that has not begun
  # cannot finish before now plus its own length. Zero when the plan is still on time.
  def self.delay(placed, now)
    worst = 0
    placed.each do |s|
      next unless s["done_at"].nil?
      behind = if s["started_at"].nil?
                 now - s["start_at"].to_i
               else
                 s["started_at"].to_i + s["minutes"].to_i * 60 - s["end_at"].to_i
               end
      worst = behind if behind > worst
    end
    worst
  end
end
