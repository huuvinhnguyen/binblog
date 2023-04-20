import { Controller } from "@hotwired/stimulus";
import consumer from "channels/consumer";

// Connects to data-controller="room"
export default class extends Controller {
  connect() {
    console.log("Hello, Stimulus!");
    this.sub = this.createActionCableChannel("1234");

    console.log(this.sub);
  }

  createActionCableChannel(roomId) {
    return consumer.subscriptions.create(
      // room_#{params[:room_id]}_channel
      { channel: "MqttChannel", room_id: roomId },
      {
        connected() {
          // Called when the subscription is ready for use on the server
        },

        disconnected() {
          // Called when the subscription has been terminated by the server
        },

        received(data) {
          // Called when there's incoming data on the websocket for this channel
          console.log(data);
        },
      }
    );
  }
}
