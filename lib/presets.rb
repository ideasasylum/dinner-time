# frozen_string_literal: true

# Starter plans. One line per step: dish | step | minutes | place | hands-on. The dish order is the order
# the lines first mention each dish, which is also the order the scheduler prefers when hands-on steps clash.
module Presets
  ROAST = [
    "Beef|Preheat oven 1|15|oven1|0",
    "Beef|Roast the beef|90|oven1|0",
    "Beef|Rest under foil|30||0",
    "Beef|Carve|10||1",
    "Roast potatoes|Peel and chop|15||1",
    "Roast potatoes|Par-boil|10|hob|0",
    "Roast potatoes|Heat the fat in the tin|10|oven1|0",
    "Roast potatoes|Roast|60|oven1|0",
    "Yorkshire puddings|Make the batter|10||1",
    "Yorkshire puddings|Rest the batter|30||0",
    "Yorkshire puddings|Preheat oven 2 and the tin|15|oven2|0",
    "Yorkshire puddings|Bake|25|oven2|0",
    "Veg|Chop the veg|15||1",
    "Veg|Steam|12|hob|0",
    "Gravy|Make the gravy|15|hob|1"
  ].freeze

  def self.lines(name)
    case name
    when "roast" then ROAST
    else []
    end
  end
end
