# encoding: utf-8

require 'uri'
require 'hocon/impl'

# There are several places in the Java codebase that
# use Java's URL constructor, and rely on it to throw
# a `MalformedURLException` if the URL isn't valid.
#
# Ruby doesn't really have a similar constructor /
# validator, so this is a little shim to hopefully
# make the ported code match up with the upstream more
# closely.
class Hocon::Impl::Url
  class MalformedUrlError < StandardError
  end

  def initialize(url)
    begin
      @url = URI.parse(url)
      if !(@url.kind_of?(URI::HTTP))
        raise MalformedUrlError, "Unrecognized URL: '#{url}'"
      end
    rescue URI::InvalidURIError
      raise MalformedUrlError, "Unrecognized URL: '#{url}'"
    end
  end
end
