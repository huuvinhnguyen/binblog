import consumer from "./consumer"
consumer.subscriptions.create("FingerprintsChannel", {
    connected() {
        console.log("Connected to FingerprintsChannel channel")
    },
    
    disconnected() {
    console.log("Disconnected from FingerprintsChannel channel")
        this.unsubscribe();
    },
    received(data) {
        console.log("FingerprintsChannel delete finger")

        if (data.action === 'delete') {
            const fingerIdElement = document.getElementById(`finger-${data.device_finger_id}`);
            if (fingerIdElement) {
                fingerIdElement.remove();  // Remove the element from the DOM
            }
        }
    }
});