/**
 * FocusDNS Enterprise Web Admin - Longitudinal Analytics & Dopamine Rehabilitation Dashboard
 * Renders interactive Canvas 7x24 distraction vulnerability heatmaps, dopamine recovery curves,
 * streak momentum charts, and exports downloadable audit reports.
 */

'use strict';

class AnalyticsDashboard {
  constructor() {
    this.currentHorizon = 'week'; // 'day', 'week', 'month', 'year', 'all'
    this.heatmapCanvas = document.getElementById('heatmap-canvas');
    this.dopamineCanvas = document.getElementById('dopamine-curve-canvas');
    this.streakContainer = document.getElementById('streak-matrix-container');

    this.domElements = {
      horizonButtons: document.querySelectorAll('.horizon-btn'),
      btnExportCsv: document.getElementById('btn-export-csv'),
      btnExportPdf: document.getElementById('btn-export-pdf'),
      statReclaimedHours: document.getElementById('stat-reclaimed-hours'),
      statStreakCount: document.getElementById('stat-streak-count'),
      statAdherenceRate: document.getElementById('stat-adherence-rate'),
      statDopamineScore: document.getElementById('stat-dopamine-score')
    };

    // Synthetic or fetched dataset
    this.analyticsData = this.generateDataset();
    this.init();
  }

  init() {
    this.bindEvents();
    this.renderHeatmap();
    this.renderDopamineCurve();
    this.renderStreakMatrix();
    this.updateSummaryStats();
  }

  bindEvents() {
    this.domElements.horizonButtons.forEach((btn) => {
      btn.addEventListener('click', (e) => {
        this.domElements.horizonButtons.forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        this.currentHorizon = btn.getAttribute('data-horizon');
        this.onHorizonChanged();
      });
    });

    if (this.domElements.btnExportCsv) {
      this.domElements.btnExportCsv.addEventListener('click', () => this.exportCsvReport());
    }

    if (this.domElements.btnExportPdf) {
      this.domElements.btnExportPdf.addEventListener('click', () => window.print());
    }

    window.addEventListener('resize', () => {
      this.renderHeatmap();
      this.renderDopamineCurve();
    });
  }

  onHorizonChanged() {
    this.updateSummaryStats();
    this.renderHeatmap();
    this.renderDopamineCurve();
  }

  /* =========================================================================
   * 1. 7x24 COGNITIVE ATTENTION HEATMAP (CANVAS)
   * ========================================================================= */

  renderHeatmap() {
    if (!this.heatmapCanvas) return;
    const ctx = this.heatmapCanvas.getContext('2d');
    const width = this.heatmapCanvas.parentElement.clientWidth || 800;
    const height = 260;

    // Handle high-DPI retina displays
    const dpr = window.devicePixelRatio || 1;
    this.heatmapCanvas.width = width * dpr;
    this.heatmapCanvas.height = height * dpr;
    this.heatmapCanvas.style.width = `${width}px`;
    this.heatmapCanvas.style.height = `${height}px`;
    ctx.scale(dpr, dpr);

    ctx.clearRect(0, 0, width, height);

    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const leftMargin = 40;
    const topMargin = 30;
    const bottomMargin = 20;

    const cellWidth = (width - leftMargin - 10) / 24;
    const cellHeight = (height - topMargin - bottomMargin) / 7;

    // Draw Hour Labels (0h to 23h)
    ctx.fillStyle = '#7a7a8c';
    ctx.font = '10px sans-serif';
    ctx.textAlign = 'center';
    for (let h = 0; h < 24; h += 2) {
      const x = leftMargin + (h * cellWidth) + (cellWidth / 2);
      ctx.fillText(`${h}:00`, x, topMargin - 10);
    }

    // Draw Day Labels (Mon to Sun)
    ctx.textAlign = 'right';
    ctx.textBaseline = 'middle';
    for (let d = 0; d < 7; d++) {
      const y = topMargin + (d * cellHeight) + (cellHeight / 2);
      ctx.fillText(days[d], leftMargin - 10, y);
    }

    // Draw 7x24 Heatmap Grid
    for (let d = 0; d < 7; d++) {
      for (let h = 0; h < 24; h++) {
        const val = this.analyticsData.heatmapGrid[d][h]; // 0 to 1 intensity
        const x = leftMargin + (h * cellWidth);
        const y = topMargin + (d * cellHeight);

        // Color ramp: Dark gray -> Low Green -> Neon Red (Distraction spikes at night)
        let color = 'rgba(255, 255, 255, 0.04)';
        if (val > 0.75) {
          color = `rgba(255, 59, 92, ${val})`; // High distraction risk
        } else if (val > 0.4) {
          color = `rgba(255, 159, 28, ${val})`; // Moderate risk
        } else if (val > 0.1) {
          color = `rgba(0, 230, 153, ${val * 0.8})`; // Safe deep focus
        }

        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.roundRect(x + 1, y + 1, cellWidth - 2, cellHeight - 2, 4);
        ctx.fill();
      }
    }
  }

  /* =========================================================================
   * 2. DOPAMINE RECEPTOR RECOVERY CURVE (CANVAS)
   * ========================================================================= */

  renderDopamineCurve() {
    if (!this.dopamineCanvas) return;
    const ctx = this.dopamineCanvas.getContext('2d');
    const width = this.dopamineCanvas.parentElement.clientWidth || 800;
    const height = 220;

    const dpr = window.devicePixelRatio || 1;
    this.dopamineCanvas.width = width * dpr;
    this.dopamineCanvas.height = height * dpr;
    this.dopamineCanvas.style.width = `${width}px`;
    this.dopamineCanvas.style.height = `${height}px`;
    ctx.scale(dpr, dpr);

    ctx.clearRect(0, 0, width, height);

    const left = 50;
    const right = width - 30;
    const top = 20;
    const bottom = height - 30;
    const plotWidth = right - left;
    const plotHeight = bottom - top;

    // Draw Axes & Grid lines
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.08)';
    ctx.lineWidth = 1;
    for (let p = 0; p <= 100; p += 25) {
      const y = bottom - (p / 100) * plotHeight;
      ctx.beginPath();
      ctx.moveTo(left, y);
      ctx.lineTo(right, y);
      ctx.stroke();

      ctx.fillStyle = '#6a6a7c';
      ctx.font = '10px sans-serif';
      ctx.textAlign = 'right';
      ctx.fillText(`${p}%`, left - 8, y + 3);
    }

    // Days on X axis (Day 0 to Day 30)
    for (let day = 0; day <= 30; day += 5) {
      const x = left + (day / 30) * plotWidth;
      ctx.fillStyle = '#6a6a7c';
      ctx.textAlign = 'center';
      ctx.fillText(`Day ${day}`, x, bottom + 16);
    }

    // Gradient fill under recovery curve
    const gradient = ctx.createLinearGradient(0, top, 0, bottom);
    gradient.addColorStop(0, 'rgba(0, 230, 153, 0.35)');
    gradient.addColorStop(1, 'rgba(0, 230, 153, 0.0)');

    ctx.beginPath();
    ctx.moveTo(left, bottom);

    // Mathematical curve: R(t) = 100 * (1 - e^(-t / 14)) + base
    const baseSensitivity = 25; // baseline pre-detox
    for (let t = 0; t <= 30; t += 0.5) {
      const x = left + (t / 30) * plotWidth;
      const sensitivity = baseSensitivity + (100 - baseSensitivity) * (1 - Math.exp(-t / 10));
      const y = bottom - (sensitivity / 100) * plotHeight;
      ctx.lineTo(x, y);
    }

    ctx.lineTo(right, bottom);
    ctx.closePath();
    ctx.fillStyle = gradient;
    ctx.fill();

    // Curve Line
    ctx.beginPath();
    for (let t = 0; t <= 30; t += 0.5) {
      const x = left + (t / 30) * plotWidth;
      const sensitivity = baseSensitivity + (100 - baseSensitivity) * (1 - Math.exp(-t / 10));
      const y = bottom - (sensitivity / 100) * plotHeight;
      if (t === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.strokeStyle = '#00e699';
    ctx.lineWidth = 3;
    ctx.stroke();

    // Current Day Pin Marker (e.g. Day 14)
    const currentDay = 14;
    const currentX = left + (currentDay / 30) * plotWidth;
    const currentSens = baseSensitivity + (100 - baseSensitivity) * (1 - Math.exp(-currentDay / 10));
    const currentY = bottom - (currentSens / 100) * plotHeight;

    ctx.fillStyle = '#ff9f1c';
    ctx.beginPath();
    ctx.arc(currentX, currentY, 6, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = '#fff';
    ctx.lineWidth = 2;
    ctx.stroke();

    // Callout text
    ctx.fillStyle = '#ffffff';
    ctx.font = 'bold 11px sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText(`Day 14: ${Math.round(currentSens)}% Sensitivity`, currentX, currentY - 12);
  }

  /* =========================================================================
   * 3. 365-DAY STREAK MOMENTUM COMMIT MATRIX
   * ========================================================================= */

  renderStreakMatrix() {
    if (!this.streakContainer) return;

    let html = '<div class="streak-calendar-grid">';
    // Render 52 weeks x 7 days
    for (let w = 0; w < 52; w++) {
      html += '<div class="streak-week-col">';
      for (let d = 0; d < 7; d++) {
        const level = Math.floor(Math.random() * 5); // 0 to 4 focus intensity
        html += `<div class="streak-cell level-${level}" title="Week ${w + 1}, Day ${d + 1}"></div>`;
      }
      html += '</div>';
    }
    html += '</div>';

    this.streakContainer.innerHTML = html;
  }

  /* =========================================================================
   * 4. SUMMARY METRICS & EXPORTS
   * ========================================================================= */

  updateSummaryStats() {
    const mult = this.getHorizonMultiplier();
    if (this.domElements.statReclaimedHours) {
      this.domElements.statReclaimedHours.textContent = `${(14.5 * mult).toFixed(1)} hrs`;
    }
    if (this.domElements.statStreakCount) {
      this.domElements.statStreakCount.textContent = `${18} Days`;
    }
    if (this.domElements.statAdherenceRate) {
      this.domElements.statAdherenceRate.textContent = '94.2%';
    }
    if (this.domElements.statDopamineScore) {
      this.domElements.statDopamineScore.textContent = '88 / 100';
    }
  }

  getHorizonMultiplier() {
    switch (this.currentHorizon) {
      case 'day': return 0.2;
      case 'week': return 1.0;
      case 'month': return 4.2;
      case 'year': return 52.0;
      default: return 60.0;
    }
  }

  exportCsvReport() {
    const rows = [
      ['Date', 'Sessions Completed', 'Traps Severed', 'Minutes Reclaimed', 'Break Overshoots Avoided', 'Dopamine Score'],
      ['2026-11-01', '6', '142', '150', '2', '82'],
      ['2026-11-02', '8', '210', '200', '4', '85'],
      ['2026-11-03', '7', '180', '175', '3', '86'],
      ['2026-11-04', '9', '255', '225', '5', '89'],
      ['2026-11-05', '5', '115', '125', '1', '84'],
      ['2026-11-06', '8', '195', '200', '3', '88'],
      ['2026-11-07', '10', '320', '250', '6', '91']
    ];

    const csvContent = "data:text/csv;charset=utf-8," + rows.map(e => e.join(",")).join("\n");
    const encodedUri = encodeURI(csvContent);
    const link = document.createElement("a");
    link.setAttribute("href", encodedUri);
    link.setAttribute("download", `focusdns_audit_report_${this.currentHorizon}.csv`);
    document.body.appendChild(link);
    link.click();
    link.remove();
  }

  generateDataset() {
    // 7 days x 24 hours matrix
    const grid = [];
    for (let d = 0; d < 7; d++) {
      const row = [];
      for (let h = 0; h < 24; h++) {
        // High risk between 21:00 and 01:00
        if (h >= 21 || h <= 1) {
          row.push(0.7 + Math.random() * 0.3);
        } else if (h >= 9 && h <= 17) {
          row.push(0.1 + Math.random() * 0.2); // Clean deep work
        } else {
          row.push(Math.random() * 0.4);
        }
      }
      grid.push(row);
    }

    return { heatmapGrid: grid };
  }
}

// Instantiate on load
document.addEventListener('DOMContentLoaded', () => {
  window.analyticsDashboard = new AnalyticsDashboard();
});
