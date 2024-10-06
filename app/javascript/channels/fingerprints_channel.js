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
        
        if (data.action === 'delete') {
            console.log("FingerprintsChannel_delete_finger")

            const fingerIdElement = document.getElementById(`finger-${data.device_finger_id}`);
            if (fingerIdElement) {
                fingerIdElement.remove();  // Remove the element from the DOM
            }
        }

        const string_data = JSON.parse(data.replace(/(?:\\[rn])+/g, ''));
        const message_hash = JSON.parse(string_data.replace(/(?:\\[rn])+/g, ''));

        if (message_hash.action === 'enroll') {
            console.log("FingerprintsChannel_enroll_finger")
            const addingFingerElement = document.getElementById('adding-finger-button');
            const enrollmentModeElement = document.getElementById('enrollment-mode');

            if (message_hash.enrollment_mode == true) {
                enrollmentModeElement.style.display = 'block';  // Show the cancel button
                addingFingerElement.style.display = 'none';    // Hide the add finger button
            } else {
                enrollmentModeElement.style.display = 'none';  // Hide the cancel button
                addingFingerElement.style.display = 'block';   // Show the add finger button
            }
            const statusElement = document.getElementById('fingerprint-status');
            if (statusElement) {
                if (message_hash.status == 'fingerprint_touch_1') {
                    statusElement.innerText = 'Vui lòng đặt ngón tay lên cảm biến';
                    statusElement.style.color = 'blue';  // Change text color to blue
                }
            
                if (message_hash.status == 'fingerprint_remove') {
                    statusElement.innerText = 'Bỏ ngón tay khỏi cảm biến';
                    statusElement.style.color = 'orange';  // Change text color to orange
                }
            
                if (message_hash.status == 'fingerprint_touch_2') {
                    statusElement.innerText = 'Đặt lại ngón tay lên cảm biến';
                    statusElement.style.color = 'purple';  // Change text color to purple
                }
            
                if (message_hash.status == 'fingerprint_stored') {
                    statusElement.innerText = 'Đã lưu ngón tay thành công';
                    statusElement.style.color = 'green';  // Change text color to green
                }
            }
            
        }

        if (message_hash.action === 'delete_fingerprint') {
            console.log("FingerprintsChannel_delete_fingerprint")

        }

    }
});
