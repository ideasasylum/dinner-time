# frozen_string_literal: true

# Wall-clock helpers that never touch the server's timezone. A plan stores its serve time as Unix seconds
# plus the browser's UTC offset in minutes (JavaScript's getTimezoneOffset, positive west of Greenwich), so
# every conversion here is integer arithmetic on that pair.
module Clock
  DAY = 86_400
  DAYS = %w[Thu Fri Sat Sun Mon Tue Wed].freeze
  MONTHS = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze

  def self.local_seconds(secs, tz_offset) = secs - tz_offset * 60

  def self.hhmm(secs, tz_offset)
    minutes = (local_seconds(secs, tz_offset) % DAY) / 60
    two(minutes / 60) + ":" + two(minutes % 60)
  end

  # "Sun 21 Sep"
  def self.day_label(secs, tz_offset)
    days = local_seconds(secs, tz_offset) / DAY
    ymd = civil(days)
    DAYS[days % 7] + " " + ymd[2].to_s + " " + MONTHS[ymd[1] - 1]
  end

  # "2026-09-21", for a date input
  def self.ymd(secs, tz_offset)
    c = civil(local_seconds(secs, tz_offset) / DAY)
    c[0].to_s + "-" + two(c[1]) + "-" + two(c[2])
  end

  # "YYYY-MM-DD" + "HH:MM" in the browser's zone -> Unix seconds, or nil when either is malformed.
  def self.parse(date, time, tz_offset)
    return nil unless date.match?(/\A\d{4}-\d\d-\d\d\z/) && time.match?(/\A\d\d:\d\d\z/)
    days = days_from_civil(date[0, 4].to_i, date[5, 2].to_i, date[8, 2].to_i)
    days * DAY + time[0, 2].to_i * 3600 + time[3, 2].to_i * 60 + tz_offset * 60
  end

  def self.duration(minutes)
    return "#{minutes} min" if minutes < 60
    h = minutes / 60
    m = minutes % 60
    m.zero? ? "#{h} h" : "#{h} h #{m} min"
  end

  def self.two(n) = n < 10 ? "0#{n}" : n.to_s

  # Days since 1970-01-01 -> [year, month, day]. Howard Hinnant's civil_from_days.
  def self.civil(days)
    z = days + 719_468
    era = (z >= 0 ? z : z - 146_096) / 146_097
    doe = z - era * 146_097
    yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
    y = yoe + era * 400
    doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    mp = (5 * doy + 2) / 153
    d = doy - (153 * mp + 2) / 5 + 1
    m = mp < 10 ? mp + 3 : mp - 9
    [m <= 2 ? y + 1 : y, m, d]
  end

  def self.days_from_civil(y, m, d)
    y -= 1 if m <= 2
    era = (y >= 0 ? y : y - 399) / 400
    yoe = y - era * 400
    doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1
    doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    era * 146_097 + doe - 719_468
  end
end
