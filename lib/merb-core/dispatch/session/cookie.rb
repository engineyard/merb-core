# encoding: UTF-8

require 'base64'        # to convert Marshal.dump to ASCII
require 'openssl'       # to generate the HMAC message digest
module Merb

  # If you have more than 4K of session data or don't want your data to be
  # visible to the user, pick another session store.
  #
  # CookieOverflow is raised if you attempt to store more than 4K of data.
  # TamperedWithCookie is raised if the data integrity check fails.
  #
  # A message digest is included with the cookie to ensure data integrity:
  # a user cannot alter session data without knowing the secret key included
  # in the hash.
  #
  # @see Merb::SessionContainer
  #
  # To use Cookie Sessions, set in `config/merb.yml`:
  #
  # * **`:session_secret_key:`** Your secret digest key
  # * **`:session_store:`** Cookie
  class CookieSession < SessionContainer
    # TODO (maybe):
    # include request ip address
    # AES encrypt marshaled data

    # Raised when storing more than 4K of session data.
    class CookieOverflow < StandardError; end

    # Raised when the cookie fails its integrity check.
    class TamperedWithCookie < StandardError; end

    # Cookies can typically store 4096 bytes.
    MAX = 4096
    DIGEST = OpenSSL::Digest::Digest.new('SHA1') # or MD5, RIPEMD160, SHA256?

    # @api private
    attr_accessor :_original_session_data

    # The session store type
    self.session_store_type = :cookie
    
    class << self
      # @see SessionContainer.generate
      # @api private
      def generate
        self.new(Merb::SessionMixin.rand_uuid, "", Merb::Request._session_secret_key)
      end

      # @see SessionContainer.setup
      # @api private
      def setup(request)
        session = self.new(Merb::SessionMixin.rand_uuid,
          request.session_cookie_value, request._session_secret_key)
        session._original_session_data = session.to_cookie
        request.session = session
      end
      
    end

    # @param [String] session_id A unique identifier for this session.
    # @param [String] cookie The raw cookie data.
    # @param [String] secret A session secret.
    #
    # @raise [ArgumentError] blank or insufficiently long secret.
    #
    # @api private
    def initialize(session_id, cookie, secret)
      super session_id
      if secret.blank? || secret.length < 16
        msg = "You must specify a session_secret_key in your init file, and it must be at least 16 characters"
        Merb.logger.warn(msg)
        raise ArgumentError, msg
      end
      @secret = secret
      self.update(unmarshal(cookie))
    end

    # @api private
    def finalize(request)
      if @_destroy
        request.destroy_session_cookie
      elsif _original_session_data != (new_session_data = self.to_cookie)
        request.set_session_cookie_value(new_session_data)
      end
    end

    # Regenerate the session_id.
    # 
    # @api private
    def regenerate
      self.session_id = Merb::SessionMixin.rand_uuid
    end

    # Create the raw cookie string; includes an HMAC keyed message digest.
    #
    # @return [String] Cookie value.
    #
    # @raise [CookieOverflow] More than 4K of data put into session.
    #
    # @note
    #   Session data is converted to a Hash first, since a container might
    #   choose to marshal it, which would make it persist attributes like
    #   `'needs_new_cookie'`, which it shouldn't.
    #
    # @api private
    def to_cookie
      unless self.empty?
        data = self.serialize
        value = Merb::Parse.escape "#{data}--#{generate_digest(data)}"
        if value.size > MAX
          msg = "Cookies have limit of 4K. Session contents: #{data.inspect}"
          Merb.logger.error!(msg)
          raise CookieOverflow, msg
        end
        value
      end
    end
    
    private

    # Generate the HMAC keyed message digest. Uses SHA1.
    #
    # @return [String] an HMAC digest of the cookie data.
    #
    # @api private
    def generate_digest(data)
      OpenSSL::HMAC.hexdigest(DIGEST, @secret, data)
    end

    # Securely compare two digests using a constant time algorithm.
    # This avoids leaking information about the calculated HMAC.
    #
    # Based on code by Michael Koziarski <michael@koziarski.com>
    #
    # @see http://github.com/rails/rails/commit/674f780d59a5a7ec0301755d43a7b277a3ad2978
    #
    # @param [#to_s] a, b digests to compare.
    #
    # @return [Boolean] Do the digests validate?
    def secure_compare(a, b)
      if a.length == b.length

        # unpack to forty characters.
        # needed for 1.8 and 1.9 compat
        a_bytes = a.unpack('C*')
        b_bytes = b.unpack('C*')

        result = 0
        for i in 0..(a_bytes.length - 1)
          result |= a_bytes[i] ^ b_bytes[i]
        end
        result == 0
      else
        false
      end
    end

    # Unmarshal cookie data to a hash and verify its integrity.
    #
    # @param [#to_s] cookie The cookie to unmarshal.
    #
    # @raise [TamperedWithCookie] The digests don't match.
    #
    # @return [Hash] The stored session data.
    #
    # @api private
    def unmarshal(cookie)
      if cookie.blank?
        {}
      else
        data, digest = Merb::Parse.unescape(cookie).split('--')
        return {} if data.blank? || digest.blank?
        unless secure_compare(generate_digest(data), digest)
          clear
          unless Merb::Config[:ignore_tampered_cookies]
            raise TamperedWithCookie, "Maybe the site's session_secret_key has changed?"
          end
        end
        unserialize(data)
      end
    end
    
    protected

    # Serialize current session data as a Hash.
    # Uses Base64 encoding for integrity.
    #
    # @return [String] Base64 encoded dump of the session hash.
    #
    # @api private
    def serialize
      Base64.encode64(Marshal.dump(self.to_hash)).chop
    end

    # Unserialize the raw cookie data to a Hash.
    #
    # @return [Hash] the session hash Base64 decoded from the data dump.
    #
    # @api private
    def unserialize(data)
      Marshal.load(Base64.decode64(data)) rescue {}
    end
  end
end
