# encoding: UTF-8

module Merb
  
  # The class attribute :store holds a reference to an object that
  # implements the following interface:
  #
  #     retrieve_session(session_id)    # returns a Hash
  #     store_session(session_id, data) # expects data to be Hash
  #     delete_session(session_id)
  #
  # You can use session store classes directly by assigning to `:store`
  # in your `config/init.rb` `after_app_loads` step, for example:
  #
  #     Merb::BootLoader.after_app_loads do
  #       SessionStoreContainer.store = MemorySession.new
  #     end
  #
  # Or you can inherit from SessionStoreContainer to create a
  # {SessionContainer} that delegates to aggregated store.
  #
  #     class MemorySession < SessionStoreContainer
  #       self.session_store_type = :memory
  #     end
  #
  #     class MemoryContainer
  #
  #       def self.retrieve_session(session_id)
  #         # ...
  #       end
  #
  #       def self.store_session(session_id, data)
  #         # ...
  #       end
  #
  #       def self.delete_session(session_id)
  #         # ...
  #       end
  #
  #     end
  # When used directly, report as `:store` store
  class SessionStoreContainer < SessionContainer
    
    class_attribute :store
    # @api private
    attr_accessor  :_fingerprint

    # Determines how many times to try generating a unique session key before we give up
    GENERATE_MAX_TRIES = 100

    self.session_store_type = :store
    
    class << self

      # Generates a new session ID and creates a new session.
      #
      # @return [SessionStoreContainer] The new session.
      #
      # @api private
      def generate
        
        # make sure we generate a unique session uuid
        sid = nil
        GENERATE_MAX_TRIES.times do |i|
          sid = Merb::SessionMixin.rand_uuid
          data = store.retrieve_session(sid) rescue nil
          break if data.nil?
          raise "Unable to Generate Unique Session key" if i == (GENERATE_MAX_TRIES-1)
        end
        
        session = new(sid)
        session.needs_new_cookie = true
        session
      end

      # Setup a new session or retreive an existing session.
      #
      # @param [Merb::Request] request The request that came in from Rack.
      #
      # @note If no sessions were found, a new SessionContainer will be generated.
      #
      # @return [SessionContainer] A SessionContainer.
      #
      # @api private
      def setup(request)
        session = retrieve(request.session_id)
        request.session = session
        # TODO Marshal.dump is slow - needs optimization
        session._fingerprint = Marshal.dump(request.session.to_hash).hash
        session
      end
            
      private

      # @param [String] session_id The ID of the session to retrieve.
      #
      # @return [SessionStoreContainer] SessionStoreContainer instance
      #   with the session data. If no sessions matched session_id, a
      #   new SessionStoreContainer will be generated.
      #
      # @note
      #   If there are persisted exceptions callbacks to execute, they
      #   all get executed when Memcache library raises an exception.
      #
      # @api private
      def retrieve(session_id)
        unless session_id.blank?
          begin
            session_data = store.retrieve_session(session_id)
          rescue => err
            Merb.logger.warn!("Could not retrieve session from #{self.name}: #{err.message}")
          end
          # Not in container, but assume that cookie exists
          session_data = new(session_id) if session_data.nil?
        else
          # No cookie...make a new session_id
          session_data = generate
        end
        if session_data.is_a?(self)
          session_data
        else
          # Recreate using the existing session as the data, when switching 
          # from another session type for example, eg. cookie to memcached
          # or when the data is just a hash
          new(session_id).update(session_data)
        end
      end

    end

    # Teardown and/or persist the current session.
    #
    # If @_destroy is true, clear out the session completely, including
    # removal of the session cookie itself.
    #
    # @param [Merb::Request] request The Merb::Request that came in from Rack.
    #
    # @note
    #   The data (self) is converted to a Hash first, since a container might
    #   choose to do a full Marshal on the data, which would make it persist
    #   attributes like 'needs_new_cookie', which it shouldn't.
    #
    # @api private
    def finalize(request)
      if @_destroy
        store.delete_session(self.session_id)
        request.destroy_session_cookie
      else
        if _fingerprint != Marshal.dump(data = self.to_hash).hash
          begin
            store.store_session(request.session(self.class.session_store_type).session_id, data)
          rescue => err
            Merb.logger.warn!("Could not persist session to #{self.class.name}: #{err.message}")
          end
        end
        if needs_new_cookie || Merb::SessionMixin.needs_new_cookie?
          request.set_session_id_cookie(self.session_id)
        end
      end
    end

    # Regenerate the session ID.
    #
    # @api private
    def regenerate
      store.delete_session(self.session_id)
      self.session_id = Merb::SessionMixin.rand_uuid
      store.store_session(self.session_id, self)
    end
    
  end
end
