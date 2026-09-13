import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

document.addEventListener("turbo:load", () => {
  const canvas = document.getElementById("pir-motion-chart")
  if (!canvas) return

  const labels = JSON.parse(canvas.dataset.labels || "[]")
  const values = JSON.parse(canvas.dataset.values || "[]")

  canvas._pirMotionChart?.destroy()

  canvas._pirMotionChart = new Chart(canvas, {
    type: "bar",
    data: {
      labels,
      datasets: [{
        label: "Lần phát hiện",
        data: values,
        backgroundColor: "rgba(110, 231, 183, 0.72)",
        borderColor: "#6EE7B7",
        borderWidth: 1,
        borderRadius: 4,
        maxBarThickness: 28
      }]
    },
    options: {
      maintainAspectRatio: false,
      responsive: true,
      plugins: {
        legend: { display: false },
        tooltip: {
          backgroundColor: "#161D2B",
          borderColor: "#3B9B7A",
          borderWidth: 1,
          titleColor: "#F3F4F6",
          bodyColor: "#F3F4F6",
          displayColors: false,
          callbacks: {
            label: (context) => `${context.parsed.y} lần phát hiện`
          }
        }
      },
      scales: {
        x: {
          grid: { display: false },
          ticks: { color: "#9CA3AF", maxRotation: 0, autoSkip: true, maxTicksLimit: 8 }
        },
        y: {
          beginAtZero: true,
          grid: { color: "rgba(156, 163, 175, 0.16)" },
          ticks: { color: "#9CA3AF", precision: 0, stepSize: 1 }
        }
      }
    }
  })
})
