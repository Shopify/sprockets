require 'benchmark'

module Sprockets
  # `Caching` is an internal mixin whose public methods are exposed on
  # the `Environment` and `Index` classes.
  module Caching
    # Low level cache getter for `key`. Checks a number of supported
    # cache interfaces.
    def cache_get(key)
      # `Cache#get(key)` for Memcache
      if cache.respond_to?(:get)
        cache.get(key)

      # `Cache#[key]` so `Hash` can be used
      elsif cache.respond_to?(:[])
        cache[key]

      # `Cache#read(key)` for `ActiveSupport::Cache` support
      elsif cache.respond_to?(:read)
        cache.read(key)

      else
        nil
      end
    end

    # Low level cache setter for `key`. Checks a number of supported
    # cache interfaces.
    def cache_set(key, value)
      # `Cache#set(key, value)` for Memcache
      if cache.respond_to?(:set)
        cache.set(key, value)

      # `Cache#[key]=value` so `Hash` can be used
      elsif cache.respond_to?(:[]=)
        cache[key] = value

      # `Cache#write(key, value)` for `ActiveSupport::Cache` support
      elsif cache.respond_to?(:write)
        cache.write(key, value)
      end

      value
    end

    protected
      # Cache helper method. Takes a `path` argument which maybe a
      # logical path or fully expanded path. The `&block` is passed
      # for finding and building the asset if its not in cache.
      def cache_asset(path)
        # If `cache` is not set, return fast
        if cache.nil?
          puts 'NO CACHE SET'
          return yield 
        end

        # Check cache for `path`
        asset = nil
        time = Benchmark.realtime { (asset = Asset.from_hash(self, cache_get_hash(path.to_s))) && asset.fresh?(self) }
        puts "CACHE #{asset ? :hit : :miss} in #{time} #{path}"

        return asset if asset

         # Otherwise yield block that slowly finds and builds the asset
        time = Benchmark.realtime { asset = yield }
        puts "BUILD in #{time} #{path}"
        
          hash = {}
          asset.encode_with(hash)

          # Save the asset to its path
          cache_set_hash(path.to_s, hash)

          # Since path maybe a logical or full pathname, save the
          # asset its its full path too
          if path.to_s != asset.pathname.to_s
            cache_set_hash(asset.pathname.to_s, hash)
          end

          asset
      end

    private
      # Strips `Environment#root` from key to make the key work
      # consisently across different servers. The key is also hashed
      # so it does not exceed 250 characters.
      def expand_cache_key(key)
        File.join('sprockets', digest_class.hexdigest(key.sub(root, '')))
      end

      def cache_get_hash(key)
        hash = nil
        time = Benchmark.realtime do
          hash = cache_get(expand_cache_key(key))
        end

        if !hash
          puts "[MISS] #{key} in #{time}"
        elsif digest.hexdigest != hash['_version']
          puts "[STALE] #{key} in #{time}"
        else
          puts "[HIT] #{key} in #{time}"
        end

        if hash.is_a?(Hash) && digest.hexdigest == hash['_version']
          hash
        end
      end

      def cache_set_hash(key, hash)
        hash['_version'] = digest.hexdigest
        cache_set(expand_cache_key(key), hash)
        hash
      end
  end
end
