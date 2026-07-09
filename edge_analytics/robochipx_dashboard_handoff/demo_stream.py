#!/usr/bin/env python3
"""Synthetic Verilog-like stream for testing the dashboard."""

from __future__ import annotations

import math
import random
import time


def main():
    moisture = 72.0
    nutrient = 76.0
    temp = 27.0
    avg_m = moisture
    avg_n = nutrient
    avg_t = temp

    print("timestamp,moisture_raw,nutrient_raw,temp_raw,moisture_avg,nutrient_avg,temp_avg,pump_on,dose_nutrient,alert_nutrient,alert_weed,alert_heat,alert_frost,alert_anomaly,status,crop_health,relocate_recommend", flush=True)

    for tick in range(1, 500):
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

        pump_on = avg_m < 35 or (90 < tick < 135)
        alert_nutrient = avg_n < 38
        dose_nutrient = avg_n < 34
        alert_heat = avg_t > 38
        alert_frost = avg_t < 4
        alert_weed = 150 < tick < 210 and avg_t < 34
        alert_anomaly = 235 <= tick < 250
        health = max(0, min(100, avg_m * 0.42 + avg_n * 0.38 + (100 - abs(avg_t - 27) * 3) * 0.20))
        critical = health < 42 or alert_heat or alert_anomaly
        warning = pump_on or alert_nutrient or alert_weed or health < 68
        status = "CRITICAL" if critical else "WARNING" if warning else "SAFE"
        relocate = int(critical and health < 35)

        row = [
            tick,
            f"{moisture:.2f}",
            f"{nutrient:.2f}",
            f"{temp:.2f}",
            f"{avg_m:.2f}",
            f"{avg_n:.2f}",
            f"{avg_t:.2f}",
            int(pump_on),
            int(dose_nutrient),
            int(alert_nutrient),
            int(alert_weed),
            int(alert_heat),
            int(alert_frost),
            int(alert_anomaly),
            status,
            f"{health:.1f}",
            relocate,
        ]
        print(",".join(map(str, row)), flush=True)
        time.sleep(0.03)


if __name__ == "__main__":
    main()
