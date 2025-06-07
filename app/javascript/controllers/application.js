import { Application } from "@hotwired/stimulus"

const application = Application.start()

// Configure Stimulus development experience
application.debug = false
window.Stimulus   = application

export { application }

import { Chart, registerables } from 'chart.js'

Chart.register(...registerables)


document.addEventListener('turbo:load', () => {
    const ctx = document.getElementById('myChart');
    if (!ctx) return;
  
    new Chart(ctx, {
      type: 'bar',
      data: {
        labels: ['Tháng 1', 'Tháng 2', 'Tháng 3', 'Tháng 4'],
        datasets: [{
          label: 'Số lượng',
          data: [12, 19, 3, 5],
          backgroundColor: ['#3490dc', '#38c172', '#ffed4a', '#e3342f'],
          borderWidth: 1
        }]
      },
      options: {
        scales: {
          y: {
            beginAtZero: true
          }
        }
      }
    });
  });
