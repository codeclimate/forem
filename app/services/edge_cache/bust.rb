module EdgeCache
  class Bust
    def initialize
      @provider_class = determine_provider_class
    end

    def self.call(*paths)
      new.call(*paths)
    end

    def call(paths)
      return unless @provider_class

      paths = Array.wrap(paths)
      paths.each do |path|
        @provider_class.call(path)
      rescue StandardError => e
        ForemStatsClient.increment(
          "edgecache_bust.provider_error",
          tags: ["provider_class:#{@provider_class}", "error_class:#{e.class}"],
        )
      end
    end

    private

    def determine_provider_class
      return self.class::Fastly if fastly_enabled?
      return self.class::Nginx if nginx_enabled_and_available?

      nil
    end

    def fastly_enabled?
      ApplicationConfig["FASTLY_API_KEY"].present? && ApplicationConfig["FASTLY_SERVICE_ID"].present?
    end

    def nginx_enabled_and_available?
      return false if ApplicationConfig["OPENRESTY_URL"].blank?

      uri = URI.parse(ApplicationConfig["OPENRESTY_URL"])
      http = Net::HTTP.new(uri.host, uri.port)
      response = http.get(uri.request_uri)

      return true if response.is_a?(Net::HTTPSuccess)
    rescue StandardError => e
      # If we can't connect to OpenResty, alert ourselves that it is
      # unavailable and return false.
      Rails.logger.error("Could not connect to OpenResty via #{ApplicationConfig['OPENRESTY_URL']}!")
      ForemStatsClient.increment("edgecache_bust.service_unavailable",
                                 tags: ["path:#{ApplicationConfig['OPENRESTY_URL']}"])
    end

    false
  end
end
