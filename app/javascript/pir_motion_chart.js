import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

const parseDate = (value) => new Date(`${value}T00:00:00`)
const formatDate = (date) => {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, "0")
  const day = String(date.getDate()).padStart(2, "0")
  return `${year}-${month}-${day}`
}

document.addEventListener("turbo:load", () => {
  const dashboard = document.getElementById("pir-motion-dashboard")
  if (!dashboard) return

  const canvas = document.getElementById("pir-motion-chart")
  const dateInput = document.getElementById("pir-motion-date")
  const totalElement = document.getElementById("pir-motion-total")
  const heatmapElement = document.getElementById("pir-motion-heatmap")
  const previousButton = document.getElementById("pir-motion-prev-day")
  const nextButton = document.getElementById("pir-motion-next-day")
  const { chipId, statsUrl, heatmapUrl } = dashboard.dataset

  if (!canvas || !dateInput || !totalElement || !heatmapElement || !chipId) return

  let chart

  const updateChart = ({ labels, values }) => {
    const data = {
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
    }

    if (chart) {
      chart.data = data
      chart.update()
      return
    }

    chart = new Chart(canvas, {
      type: "bar",
      data,
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
            callbacks: { label: (context) => `${context.parsed.y} lần phát hiện` }
          }
        },
        scales: {
          x: { grid: { display: false }, ticks: { color: "#9CA3AF", maxRotation: 0, autoSkip: true, maxTicksLimit: 8 } },
          y: { beginAtZero: true, grid: { color: "rgba(156, 163, 175, 0.16)" }, ticks: { color: "#9CA3AF", precision: 0, stepSize: 1 } }
        }
      }
    })
  }

  const setSelectedHeatmapDay = (selectedDate) => {
    heatmapElement.querySelectorAll("button").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.date === selectedDate))
    })
  }

  const loadStats = async (date) => {
    totalElement.textContent = "Đang tải…"

    try {
      const response = await fetch(`${statsUrl}?chip_id=${encodeURIComponent(chipId)}&date=${encodeURIComponent(date)}`, {
        headers: { Accept: "application/json" }
      })
      if (!response.ok) throw new Error("Không thể tải thống kê")

      const data = await response.json()
      updateChart(data)
      totalElement.textContent = `${data.total} lần trong ngày`
      setSelectedHeatmapDay(date)
    } catch (error) {
      totalElement.textContent = "Không thể tải dữ liệu"
      console.error("PIR motion stats error:", error)
    }
  }

  const renderHeatmap = (entries, maxCount) => {
    heatmapElement.replaceChildren()

    entries.forEach(({ date, count }) => {
      const level = count === 0 ? 0 : Math.min(4, Math.ceil((count / Math.max(maxCount, 1)) * 4))
      const button = document.createElement("button")
      button.type = "button"
      button.className = "pir-device__heatmap-day"
      button.dataset.date = date
      button.dataset.level = String(level)
      button.setAttribute("aria-label", `${date}: ${count} lần phát hiện`)
      button.setAttribute("aria-pressed", "false")
      button.title = `${date}: ${count} lần phát hiện`
      button.addEventListener("click", () => {
        dateInput.value = date
        loadStats(date)
      })
      heatmapElement.append(button)
    })

    setSelectedHeatmapDay(dateInput.value)
  }

  const loadHeatmap = async () => {
    try {
      const response = await fetch(`${heatmapUrl}?chip_id=${encodeURIComponent(chipId)}&days=30`, {
        headers: { Accept: "application/json" }
      })
      if (!response.ok) throw new Error("Không thể tải heatmap")

      const data = await response.json()
      renderHeatmap(data.data, data.max_count)
    } catch (error) {
      console.error("PIR heatmap error:", error)
    }
  }

  dateInput.addEventListener("change", () => loadStats(dateInput.value))
  previousButton?.addEventListener("click", () => {
    const date = parseDate(dateInput.value)
    date.setDate(date.getDate() - 1)
    dateInput.value = formatDate(date)
    loadStats(dateInput.value)
  })
  nextButton?.addEventListener("click", () => {
    const date = parseDate(dateInput.value)
    date.setDate(date.getDate() + 1)
    dateInput.value = formatDate(date)
    loadStats(dateInput.value)
  })

  loadHeatmap()
  loadStats(dateInput.value)
})
