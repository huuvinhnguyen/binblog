// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "channels"

import "popper"
import "bootstrap"

import "jquery"
import "jquery_ujs"

import "gauges"
import "device_switch"

// $(document).ready(function() {
//     if ($('#dht-form-wrapper').length) {

//         function sendConnectDhtRequest() {
//         $.ajax({
//             url: "devices/connect_dht", // Ensure this matches the route in your Rails app
//             type: "POST",
//             dataType: "script", // Expect JavaScript response if needed
//             success: function(response) {
//             console.log("Request successful");
//             // Handle the response if needed
//             },
//             error: function(xhr, status, error) {
//             console.error("Request failed:", error);
//             }
//         });
//         }
    
//         // Send request every second
//         setInterval(sendConnectDhtRequest, 5000);
//     }
//   });
