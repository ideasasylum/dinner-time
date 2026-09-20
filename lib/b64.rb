# frozen_string_literal: true

# base64url without padding: the encoding every WebAuthn and Web Push value arrives in. Decoding pads first,
# because browsers strip the padding and Ruby's decoder insists on it.
#
# Decoding answers "" rather than nil for anything malformed, and that is not only taste. Spinel infers one
# type per expression across every call site, so a helper returning String-or-nil makes String-or-nil of
# every parameter it feeds; a byte read on one of those then fails to resolve and raises NoMethodError for a
# method that plainly exists. Keeping nil out of the pipeline keeps the types pinned.
module B64
  def self.encode(bin) = Base64.urlsafe_encode64(bin, padding: false)

  def self.decode(text)
    padded = text + "=" * ((4 - text.bytesize % 4) % 4)
    Base64.urlsafe_decode64(padded)
  end

  # For values off the network, where malformed input is an answer rather than an exception.
  def self.decode_or_empty(text)
    return "" if text.empty?
    decode(text)
  rescue ArgumentError
    ""
  end
end
