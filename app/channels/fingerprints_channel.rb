class FingerprintsChannel < ApplicationCable::Channel
  def subscribed
    # stream_from "some_channel"
    @subscription = stream_from "fingerprints_channel"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
