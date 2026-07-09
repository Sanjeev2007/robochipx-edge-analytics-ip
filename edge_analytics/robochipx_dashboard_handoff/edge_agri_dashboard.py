#!/usr/bin/env python3
"""
ROBOCHIPX '26 Smart Agriculture Edge Analytics dashboard.

Run with live Verilog simulation output:
    vvp simulation.vvp | python edge_agri_dashboard.py

Run the bundled demo stream:
    python demo_stream.py | python edge_agri_dashboard.py
"""

from __future__ import annotations

import argparse
import math
import queue
import random
import sys
import threading
import time
import tkinter as tk
from collections import deque
from dataclasses import dataclass
from tkinter import ttk


FIELDS = [
    "timestamp",
    "moisture_raw",
    "nutrient_raw",
    "temp_raw",
    "moisture_avg",
    "nutrient_avg",
    "temp_avg",
    "pump_on",
    "dose_nutrient",
    "alert_nutrient",
    "alert_weed",
    "alert_heat",
    "alert_frost",
    "alert_anomaly",
    "status",
    "crop_health",
    "relocate_recommend",
]

STATUS_NAMES = {0: "SAFE", 1: "WARNING", 2: "CRITICAL", "0": "SAFE", "1": "WARNING", "2": "CRITICAL"}
STATUS_COLORS = {"SAFE": "#35d07f", "WARNING": "#ffd166", "CRITICAL": "#ff5c7a"}

BG = "#11161d"
PANEL = "#18212b"
PANEL_2 = "#202b36"
TEXT = "#eef5f0"
MUTED = "#93a4ad"
GRID = "#31414f"
GREEN = "#35d07f"
CYAN = "#5cc8ff"
YELLOW = "#ffd166"
RED = "#ff5c7a"
PURPLE = "#b69cff"
BLUE = "#6ea8fe"


@dataclass
class Sample:
    timestamp: float = 0.0
    received_at: str = ""
    moisture_raw: float = 0.0
    nutrient_raw: float = 0.0
    temp_raw: float = 0.0
    moisture_avg: float = 0.0
    nutrient_avg: float = 0.0
    temp_avg: float = 0.0
    pump_on: int = 0
    dose_nutrient: int = 0
    alert_nutrient: int = 0
    alert_weed: int = 0
    alert_heat: int = 0
    alert_frost: int = 0
    alert_anomaly: int = 0
    status: str = "SAFE"
    crop_health: float = 100.0
    relocate_recommend: int = 0


def as_float(value: str, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def as_int(value: str, default: int = 0) -> int:
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def normalize_status(value: str) -> str:
    cleaned = str(value).strip().upper()
    return STATUS_NAMES.get(cleaned, cleaned if cleaned in STATUS_COLORS else "SAFE")


def parse_sample(line: str) -> Sample | None:
    line = line.strip()
    if not line or line.startswith("#") or line.lower().startswith("timestamp"):
        return None

    if "=" in line:
        values = {}
        for token in line.replace(",", " ").split():
            if "=" not in token:
                continue
            key, value = token.split("=", 1)
            values[key.strip()] = value.strip()
    else:
        delimiter = "," if "," in line else None
        parts = [part.strip() for part in line.split(delimiter) if part.strip()]
        if len(parts) < 8:
            return None
        values = dict(zip(FIELDS, parts))

    return Sample(
        timestamp=as_float(values.get("timestamp", values.get("time", 0))),
        received_at=time.strftime("%H:%M:%S"),
        moisture_raw=as_float(values.get("moisture_raw", values.get("moisture", 0))),
        nutrient_raw=as_float(values.get("nutrient_raw", values.get("nutrient", 0))),
        temp_raw=as_float(values.get("temp_raw", values.get("temperature_raw", values.get("temp", 0)))),
        moisture_avg=as_float(values.get("moisture_avg", values.get("moisture_smooth", values.get("moisture", 0)))),
        nutrient_avg=as_float(values.get("nutrient_avg", values.get("nutrient_smooth", values.get("nutrient", 0)))),
        temp_avg=as_float(values.get("temp_avg", values.get("temperature_avg", values.get("temp", 0)))),
        pump_on=as_int(values.get("pump_on", 0)),
        dose_nutrient=as_int(values.get("dose_nutrient", values.get("dose", 0))),
        alert_nutrient=as_int(values.get("alert_nutrient", 0)),
        alert_weed=as_int(values.get("alert_weed", 0)),
        alert_heat=as_int(values.get("alert_heat", 0)),
        alert_frost=as_int(values.get("alert_frost", 0)),
        alert_anomaly=as_int(values.get("alert_anomaly", values.get("alert_fault", 0))),
        status=normalize_status(values.get("status", 0)),
        crop_health=as_float(values.get("crop_health", values.get("health", 100))),
        relocate_recommend=as_int(values.get("relocate_recommend", values.get("relocate", 0))),
    )


class Sparkline(tk.Canvas):
    def __init__(self, master, title: str, y_label: str, color_raw: str, color_avg: str, ymin: float, ymax: float):
        super().__init__(master, bg=PANEL, highlightthickness=0, height=170)
        self.title = title
        self.y_label = y_label
        self.color_raw = color_raw
        self.color_avg = color_avg
        self.ymin = ymin
        self.ymax = ymax

    def draw(self, raw_values: list[float], avg_values: list[float], threshold: float | None = None):
        self.delete("all")
        width = max(self.winfo_width(), 320)
        height = max(self.winfo_height(), 160)
        left, right, top, bottom = 46, width - 18, 34, height - 28

        self.create_text(left, 16, text=self.title, fill=TEXT, anchor="w", font=("Segoe UI", 12, "bold"))
        self.create_text(right, 16, text=self.y_label, fill=MUTED, anchor="e", font=("Segoe UI", 9))

        for i in range(4):
            y = top + (bottom - top) * i / 3
            self.create_line(left, y, right, y, fill=GRID)

        if threshold is not None:
            y = self._scale_y(threshold, top, bottom)
            self.create_line(left, y, right, y, fill=YELLOW, dash=(5, 5), width=1)
            self.create_text(right - 4, y - 8, text=f"thr {threshold:g}", fill=YELLOW, anchor="e", font=("Segoe UI", 8))

        self._draw_series(raw_values, left, right, top, bottom, self.color_raw, 1, dash=(3, 4))
        self._draw_series(avg_values, left, right, top, bottom, self.color_avg, 3)

        self.create_text(left, bottom + 16, text="raw dashed", fill=self.color_raw, anchor="w", font=("Segoe UI", 8))
        self.create_text(left + 82, bottom + 16, text="avg solid", fill=self.color_avg, anchor="w", font=("Segoe UI", 8, "bold"))

    def _scale_y(self, value: float, top: int, bottom: int) -> float:
        value = max(self.ymin, min(self.ymax, value))
        return bottom - ((value - self.ymin) / (self.ymax - self.ymin)) * (bottom - top)

    def _draw_series(self, values: list[float], left: int, right: int, top: int, bottom: int, color: str, width: int, dash=None):
        if len(values) < 2:
            return
        points = []
        for index, value in enumerate(values):
            x = left + index * (right - left) / (len(values) - 1)
            y = self._scale_y(value, top, bottom)
            points.extend([x, y])
        self.create_line(*points, fill=color, width=width, smooth=True, dash=dash)


class SignalLamp(ttk.Frame):
    def __init__(self, master, label: str, color: str):
        super().__init__(master, style="Panel.TFrame")
        self.color = color
        self.canvas = tk.Canvas(self, width=22, height=22, bg=PANEL, highlightthickness=0)
        self.canvas.grid(row=0, column=0, padx=(0, 10), pady=6)
        ttk.Label(self, text=label, style="Body.TLabel").grid(row=0, column=1, sticky="w")
        self.columnconfigure(1, weight=1)
        self.set(False)

    def set(self, active: bool):
        fill = self.color if active else "#344350"
        outline = self.color if active else "#52616d"
        self.canvas.delete("all")
        self.canvas.create_oval(3, 3, 19, 19, fill=fill, outline=outline, width=2)


class Dashboard(tk.Tk):
    def __init__(self, sample_queue: queue.Queue[Sample], speed: float):
        super().__init__()
        self.sample_queue = sample_queue
        self.speed = speed
        self.title("ROBOCHIPX '26 Edge Analytics IP Dashboard")
        self.geometry("1280x820")
        self.minsize(980, 660)
        self.configure(bg=BG)

        self.samples: deque[Sample] = deque(maxlen=120)
        self.last_sample = Sample()
        self.start_wall = time.time()
        self.frames_seen = 0

        self._configure_styles()
        self._build_layout()
        self.after(80, self._tick)

    def _configure_styles(self):
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure("Root.TFrame", background=BG)
        style.configure("Panel.TFrame", background=PANEL)
        style.configure("Panel2.TFrame", background=PANEL_2)
        style.configure("Title.TLabel", background=BG, foreground=TEXT, font=("Segoe UI", 22, "bold"))
        style.configure("Subtle.TLabel", background=BG, foreground=MUTED, font=("Segoe UI", 10))
        style.configure("Body.TLabel", background=PANEL, foreground=TEXT, font=("Segoe UI", 10))
        style.configure("Metric.TLabel", background=PANEL, foreground=TEXT, font=("Segoe UI", 20, "bold"))
        style.configure("MutedPanel.TLabel", background=PANEL, foreground=MUTED, font=("Segoe UI", 9))
        style.configure("Badge.TLabel", background=PANEL_2, foreground=TEXT, font=("Segoe UI", 16, "bold"), padding=(14, 8))

    def _build_layout(self):
        root = ttk.Frame(self, style="Root.TFrame", padding=18)
        root.pack(fill="both", expand=True)
        root.columnconfigure(0, weight=3)
        root.columnconfigure(1, weight=1)
        root.rowconfigure(1, weight=1)

        header = ttk.Frame(root, style="Root.TFrame")
        header.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 14))
        header.columnconfigure(0, weight=1)
        ttk.Label(header, text="Smart Agriculture Edge Analytics IP", style="Title.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(header, text="SENSE > SMOOTH > DECIDE > ACT", style="Subtle.TLabel").grid(row=1, column=0, sticky="w")
        self.connection_label = ttk.Label(header, text="waiting for stream", style="Subtle.TLabel")
        self.connection_label.grid(row=0, column=1, rowspan=2, sticky="e")

        charts = ttk.Frame(root, style="Root.TFrame")
        charts.grid(row=1, column=0, sticky="nsew", padx=(0, 14))
        charts.columnconfigure(0, weight=1)
        for i in range(3):
            charts.rowconfigure(i, weight=1)

        self.moisture_chart = Sparkline(charts, "Soil Moisture", "%", "#5d7d91", GREEN, 0, 100)
        self.nutrient_chart = Sparkline(charts, "Nutrient / NPK", "%", "#806d43", YELLOW, 0, 100)
        self.temp_chart = Sparkline(charts, "Temperature", "C", "#6a6f87", RED, -5, 55)
        self.moisture_chart.grid(row=0, column=0, sticky="nsew", pady=(0, 10))
        self.nutrient_chart.grid(row=1, column=0, sticky="nsew", pady=(0, 10))
        self.temp_chart.grid(row=2, column=0, sticky="nsew")

        side = ttk.Frame(root, style="Root.TFrame")
        side.grid(row=1, column=1, sticky="nsew")
        side.columnconfigure(0, weight=1)

        self.status_box = ttk.Frame(side, style="Panel2.TFrame", padding=16)
        self.status_box.grid(row=0, column=0, sticky="ew", pady=(0, 12))
        self.status_text = ttk.Label(self.status_box, text="SAFE", style="Badge.TLabel", anchor="center")
        self.status_text.pack(fill="x")
        ttk.Label(self.status_box, text="overall crop verdict", style="MutedPanel.TLabel", background=PANEL_2).pack(pady=(8, 0))

        health_panel = ttk.Frame(side, style="Panel.TFrame", padding=16)
        health_panel.grid(row=1, column=0, sticky="ew", pady=(0, 12))
        ttk.Label(health_panel, text="Crop Health", style="Body.TLabel").pack(anchor="w")
        self.health_canvas = tk.Canvas(health_panel, height=34, bg=PANEL, highlightthickness=0)
        self.health_canvas.pack(fill="x", pady=(10, 4))
        self.health_label = ttk.Label(health_panel, text="100%", style="Metric.TLabel")
        self.health_label.pack(anchor="e")

        values = ttk.Frame(side, style="Panel.TFrame", padding=16)
        values.grid(row=2, column=0, sticky="ew", pady=(0, 12))
        self.metric_labels: dict[str, ttk.Label] = {}
        metric_rows = [
            ("timestamp", "Sensor Timestamp"),
            ("received_at", "Dashboard Received"),
            ("moisture_avg", "Moisture Avg"),
            ("nutrient_avg", "Nutrient Avg"),
            ("temp_avg", "Temperature Avg"),
        ]
        for row, (name, title) in enumerate(metric_rows):
            ttk.Label(values, text=title, style="MutedPanel.TLabel").grid(row=row, column=0, sticky="w", pady=4)
            label = ttk.Label(values, text="-", style="Body.TLabel")
            label.grid(row=row, column=1, sticky="e", pady=4)
            self.metric_labels[name] = label
        values.columnconfigure(1, weight=1)

        signals = ttk.Frame(side, style="Panel.TFrame", padding=16)
        signals.grid(row=3, column=0, sticky="nsew")
        ttk.Label(signals, text="Actuators & Alerts", style="Body.TLabel").pack(anchor="w", pady=(0, 8))
        self.lamps = {
            "pump_on": SignalLamp(signals, "Pump On", GREEN),
            "dose_nutrient": SignalLamp(signals, "Nutrient Doser", YELLOW),
            "alert_nutrient": SignalLamp(signals, "Low Nutrient", YELLOW),
            "alert_weed": SignalLamp(signals, "Weed / Resource Theft", PURPLE),
            "alert_heat": SignalLamp(signals, "Heat Stress", RED),
            "alert_frost": SignalLamp(signals, "Frost Risk", CYAN),
            "alert_anomaly": SignalLamp(signals, "Sensor Anomaly", BLUE),
            "relocate_recommend": SignalLamp(signals, "Relocate Recommend", RED),
        }
        for lamp in self.lamps.values():
            lamp.pack(fill="x", pady=1)

    def _tick(self):
        pulled = 0
        while pulled < 8:
            try:
                sample = self.sample_queue.get_nowait()
            except queue.Empty:
                break
            self.samples.append(sample)
            self.last_sample = sample
            self.frames_seen += 1
            pulled += 1

        if self.samples:
            self._redraw()
        self.after(max(20, int(100 * self.speed)), self._tick)

    def _redraw(self):
        moisture_raw = [s.moisture_raw for s in self.samples]
        moisture_avg = [s.moisture_avg for s in self.samples]
        nutrient_raw = [s.nutrient_raw for s in self.samples]
        nutrient_avg = [s.nutrient_avg for s in self.samples]
        temp_raw = [s.temp_raw for s in self.samples]
        temp_avg = [s.temp_avg for s in self.samples]

        self.moisture_chart.draw(moisture_raw, moisture_avg, threshold=35)
        self.nutrient_chart.draw(nutrient_raw, nutrient_avg, threshold=38)
        self.temp_chart.draw(temp_raw, temp_avg, threshold=38)

        sample = self.last_sample
        status = normalize_status(sample.status)
        status_color = STATUS_COLORS[status]
        self.status_text.configure(text=status, background=status_color, foreground="#11161d")
        self.status_box.configure(style="Panel2.TFrame")
        self.connection_label.configure(text=f"streaming {self.frames_seen} samples | last received {sample.received_at}")

        self.metric_labels["timestamp"].configure(text=f"{sample.timestamp:g}")
        self.metric_labels["received_at"].configure(text=sample.received_at)
        self.metric_labels["moisture_avg"].configure(text=f"{sample.moisture_avg:5.1f}%")
        self.metric_labels["nutrient_avg"].configure(text=f"{sample.nutrient_avg:5.1f}%")
        self.metric_labels["temp_avg"].configure(text=f"{sample.temp_avg:5.1f} C")

        self._draw_health(sample.crop_health)
        for name, lamp in self.lamps.items():
            lamp.set(bool(getattr(sample, name)))

    def _draw_health(self, health: float):
        self.health_canvas.delete("all")
        width = max(self.health_canvas.winfo_width(), 220)
        health = max(0, min(100, health))
        fill_width = int((width - 4) * health / 100)
        color = GREEN if health >= 70 else YELLOW if health >= 40 else RED
        self.health_canvas.create_rectangle(2, 9, width - 2, 27, fill="#344350", outline="")
        self.health_canvas.create_rectangle(2, 9, fill_width, 27, fill=color, outline="")
        self.health_label.configure(text=f"{health:.0f}%")


def stdin_reader(out: queue.Queue[Sample], pace: float):
    for line in sys.stdin:
        sample = parse_sample(line)
        if sample is not None:
            out.put(sample)
            if pace > 0:
                time.sleep(pace)


def demo_reader(out: queue.Queue[Sample], pace: float):
    tick = 0
    moisture = 72.0
    nutrient = 76.0
    temp = 27.0
    avg_m = moisture
    avg_n = nutrient
    avg_t = temp
    while True:
        tick += 1
        if tick < 90:
            moisture -= 0.28
            nutrient -= 0.08
            temp = 27 + math.sin(tick / 12) * 1.5
        elif tick < 145:
            moisture += 0.72
            nutrient -= 0.10
            temp = 29 + math.sin(tick / 9) * 1.2
        elif tick < 210:
            moisture -= 0.55
            nutrient -= 0.32
            temp = 28 + math.sin(tick / 10)
        else:
            moisture += 0.15
            nutrient += 0.20
            temp = 40 + math.sin(tick / 6) * 2.0

        moisture = max(12, min(88, moisture + random.uniform(-1.7, 1.7)))
        nutrient = max(18, min(90, nutrient + random.uniform(-1.2, 1.2)))
        temp = max(-2, min(48, temp + random.uniform(-0.6, 0.6)))
        avg_m = avg_m * 0.82 + moisture * 0.18
        avg_n = avg_n * 0.84 + nutrient * 0.16
        avg_t = avg_t * 0.80 + temp * 0.20

        pump_on = avg_m < 35 or (tick > 90 and tick < 135)
        alert_nutrient = avg_n < 38
        dose_nutrient = avg_n < 34
        alert_heat = avg_t > 38
        alert_frost = avg_t < 4
        alert_weed = 150 < tick < 210 and avg_t < 34
        alert_anomaly = tick in range(235, 250)
        health = max(0, min(100, (avg_m * 0.42 + avg_n * 0.38 + (100 - abs(avg_t - 27) * 3) * 0.20)))
        critical = health < 42 or alert_heat or alert_anomaly
        warning = pump_on or alert_nutrient or alert_weed or health < 68
        status = "CRITICAL" if critical else "WARNING" if warning else "SAFE"

        out.put(
            Sample(
                timestamp=tick,
                received_at=time.strftime("%H:%M:%S"),
                moisture_raw=moisture,
                nutrient_raw=nutrient,
                temp_raw=temp,
                moisture_avg=avg_m,
                nutrient_avg=avg_n,
                temp_avg=avg_t,
                pump_on=int(pump_on),
                dose_nutrient=int(dose_nutrient),
                alert_nutrient=int(alert_nutrient),
                alert_weed=int(alert_weed),
                alert_heat=int(alert_heat),
                alert_frost=int(alert_frost),
                alert_anomaly=int(alert_anomaly),
                status=status,
                crop_health=health,
                relocate_recommend=int(critical and health < 35),
            )
        )
        time.sleep(pace)


def main():
    parser = argparse.ArgumentParser(description="Live dashboard for the ROBOCHIPX edge analytics simulation.")
    parser.add_argument("--demo", action="store_true", help="ignore stdin and generate synthetic smart-agriculture samples")
    parser.add_argument("--pace", type=float, default=0.10, help="seconds to pause per simulation sample")
    args = parser.parse_args()

    samples: queue.Queue[Sample] = queue.Queue()
    use_demo = args.demo or sys.stdin.isatty()
    target = demo_reader if use_demo else stdin_reader
    thread = threading.Thread(target=target, args=(samples, max(0.0, args.pace)), daemon=True)
    thread.start()

    app = Dashboard(samples, speed=max(0.05, args.pace))
    app.mainloop()


if __name__ == "__main__":
    main()
