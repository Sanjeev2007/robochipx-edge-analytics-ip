# ROBOCHIPX '26 Dashboard Integration Contract

Use this command for the live demo:

```powershell
vvp simulation.vvp | python edge_agri_dashboard.py
```

For a dashboard-only test:

```powershell
python demo_stream.py | python edge_agri_dashboard.py
```

## Recommended Frozen Line Format

Print one CSV row per processed sample from the Verilog testbench:

```text
timestamp,moisture_raw,nutrient_raw,temp_raw,moisture_avg,nutrient_avg,temp_avg,pump_on,dose_nutrient,alert_nutrient,alert_weed,alert_heat,alert_frost,alert_anomaly,status,crop_health,relocate_recommend
```

Example:

```text
42,31,64,29,34,66,28,1,0,0,0,0,0,0,WARNING,72,0
```

`timestamp` should be the sensor/sample timestamp from the simulation, such as a sample counter, the sensor collector timestamp, or `$time`. The dashboard also shows a separate "Dashboard Received" wall-clock time when Python receives the sample.

## What To Install

No external Python packages are required. The dashboard uses only Python standard-library modules: `tkinter`, `queue`, `threading`, `collections`, `dataclasses`, `argparse`, `math`, `random`, `time`, and `sys`.

On your teammate's VS Code machine:

1. Install Python 3.10+ from python.org.
2. Check the GUI module with `python -m tkinter`. A small window should open.
3. Install Icarus Verilog for `iverilog` and `vvp`.
4. Optional VS Code extensions: Python, Verilog-HDL/SystemVerilog support.

If `python -m tkinter` fails, install the official Python build from python.org because it includes Tkinter on Windows.

## Field Meaning

| Field | Meaning |
| --- | --- |
| `timestamp` | Simulation sample index or RTL timestamp. |
| `moisture_raw`, `nutrient_raw`, `temp_raw` | Unsmooth sensor values. |
| `moisture_avg`, `nutrient_avg`, `temp_avg` | Moving-average filter outputs. |
| `pump_on` | Irrigation actuator output. |
| `dose_nutrient` | Fertilizer dosing actuator output. |
| `alert_nutrient` | Low NPK warning. |
| `alert_weed` | Resource-theft / weed anomaly warning. |
| `alert_heat` | Heat-stress warning. |
| `alert_frost` | Frost-risk warning. |
| `alert_anomaly` | Sensor fault / impossible or stuck reading. |
| `status` | `SAFE`, `WARNING`, `CRITICAL`, or numeric `0`, `1`, `2`. |
| `crop_health` | 0-100 fused plant-health score. |
| `relocate_recommend` | 1 when environment remains critical despite action. |

## Verilog Testbench Print Snippet

Put the header once, then print a row whenever the top module finishes one sample:

```verilog
initial begin
  $display("timestamp,moisture_raw,nutrient_raw,temp_raw,moisture_avg,nutrient_avg,temp_avg,pump_on,dose_nutrient,alert_nutrient,alert_weed,alert_heat,alert_frost,alert_anomaly,status,crop_health,relocate_recommend");
end

always @(posedge clk) begin
  if (sample_valid) begin
    $display("%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
      timestamp,
      moisture_raw, nutrient_raw, temp_raw,
      moisture_avg, nutrient_avg, temp_avg,
      pump_on, dose_nutrient, alert_nutrient, alert_weed,
      alert_heat, alert_frost, alert_anomaly,
      status,
      crop_health,
      relocate_recommend
    );
    $fflush;
  end
end
```

Print `status` as `0`, `1`, or `2`. The dashboard maps them to `SAFE`, `WARNING`, and `CRITICAL`.

The dashboard also accepts `key=value` tokens during debugging, for example:

```text
time=42 moisture=31 moisture_avg=34 nutrient=64 nutrient_avg=66 temp=29 temp_avg=28 pump_on=1 status=WARNING crop_health=72
```

## Do We Need The Verilog Code First?

No. Build the dashboard first against this frozen line format, then connect the real Verilog simulation later. Your teammate only needs to make the testbench print the same fields in the same order. That is why `demo_stream.py` exists: it lets the dashboard be tested before the RTL is complete.
