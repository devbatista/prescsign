module Prescsign
  class RateLimiter
    class << self
      def hit!(bucket:, identifier:, period:)
        key = cache_key(bucket: bucket, identifier: identifier)
        current = store.read(key).to_i

        if current <= 0
          store.write(key, 1, expires_in: period)
          return 1
        end

        incremented = store.increment(key, 1)
        return incremented.to_i if incremented

        fallback = current + 1
        store.write(key, fallback, expires_in: period)
        fallback
      end

      def clear!
        fallback_store&.clear
      end

      private

      def cache_key(bucket:, identifier:)
        "rate_limit:#{bucket}:#{identifier}"
      end

      def store
        return Rails.cache unless Rails.cache.is_a?(ActiveSupport::Cache::NullStore)

        self.fallback_store ||= ActiveSupport::Cache::MemoryStore.new
      end

      attr_accessor :fallback_store
    end
  end
end
