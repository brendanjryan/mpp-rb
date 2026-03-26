# frozen_string_literal: true

require "time"

module Mpp
  module Expires
    module_function

    # Format a Time as ISO 8601 with Z suffix and millisecond precision.
    def to_iso(time)
      time.utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ")
    end

    # Returns an ISO 8601 datetime string n seconds from now.
    def seconds(n)
      to_iso(Time.now.utc + n)
    end

    # Returns an ISO 8601 datetime string n minutes from now.
    def minutes(n)
      to_iso(Time.now.utc + (n * 60))
    end

    # Returns an ISO 8601 datetime string n hours from now.
    def hours(n)
      to_iso(Time.now.utc + (n * 3600))
    end

    # Returns an ISO 8601 datetime string n days from now.
    def days(n)
      to_iso(Time.now.utc + (n * 86_400))
    end

    # Returns an ISO 8601 datetime string n weeks from now.
    def weeks(n)
      to_iso(Time.now.utc + (n * 7 * 86_400))
    end

    # Returns an ISO 8601 datetime string n months (30 days) from now.
    def months(n)
      to_iso(Time.now.utc + (n * 30 * 86_400))
    end

    # Returns an ISO 8601 datetime string n years (365 days) from now.
    def years(n)
      to_iso(Time.now.utc + (n * 365 * 86_400))
    end
  end
end
