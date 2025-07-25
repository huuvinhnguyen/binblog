import { Application } from '@hotwired/stimulus'

import * as Turbo from '@hotwired/turbo'
window.Turbo = Turbo

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


document.addEventListener('turbo:load', () => {

    const ctx = document.getElementById('tempHumidityChart').getContext('2d');

    const tempHumidityChart = new Chart(ctx, {
        type: 'line',
        data: {
        labels: ['09:00', '10:00', '11:00', '12:00', '13:00', '14:00'], // Thời gian
        datasets: [
            {
            label: 'Nhiệt độ (°C)',
            data: [26, 27, 28, 29, 28, 27],
            borderColor: 'rgba(255, 99, 132, 1)',
            backgroundColor: 'rgba(255, 99, 132, 0.2)',
            tension: 0.3,
            },
            {
            label: 'Độ ẩm (%)',
            data: [60, 62, 63, 61, 60, 59],
            borderColor: 'rgba(54, 162, 235, 1)',
            backgroundColor: 'rgba(54, 162, 235, 0.2)',
            tension: 0.3,
            }
        ]
        },
        options: {
        responsive: true,
        interaction: {
            mode: 'index',
            intersect: false,
        },
        stacked: false,
        scales: {
            y: {
            beginAtZero: false,
            title: {
                display: true,
                text: 'Giá trị'
            }
            },
            x: {
            title: {
                display: true,
                text: 'Thời gian'
            }
            }
        },
        plugins: {
            legend: {
            position: 'top',
            },
            title: {
            display: true,
            text: 'Biểu đồ Nhiệt độ và Độ ẩm theo thời gian'
            }
        }
        }
    });
});


document.addEventListener('turbo:load', () => {

    // Sample data: số lần chuyển động ghi nhận mỗi giờ
    const motionData = [
        { hour: '08:00', motion_count: 2 },
        { hour: '09:00', motion_count: 5 },
        { hour: '10:00', motion_count: 3 },
        { hour: '11:00', motion_count: 7 },
        { hour: '12:00', motion_count: 4 },
        { hour: '13:00', motion_count: 0 },
        { hour: '14:00', motion_count: 6 }
    ];

    const labels = motionData.map(entry => entry.hour);
    const data = motionData.map(entry => entry.motion_count);

    const ctx = document.getElementById('motionChart').getContext('2d');
    const motionChart = new Chart(ctx, {
        type: 'bar',
        data: {
        labels: labels,
        datasets: [{
            label: 'Số lần chuyển động',
            data: data,
            backgroundColor: 'rgba(255, 99, 132, 0.6)',
            borderColor: 'rgba(255, 99, 132, 1)',
            borderWidth: 1
        }]
        },
        options: {
        responsive: true,
        scales: {
            y: {
            beginAtZero: true,
            ticks: { stepSize: 1 }
            }
        }
        }
    });

  });
