# Send This To The Verilog Teammate

Files:

- `edge_agri_dashboard.py` - the actual dashboard.
- `demo_stream.py` - fake data generator for testing the dashboard before RTL integration.
- `VERILOG_DASHBOARD_CONTRACT.md` - exact data format and Verilog print snippet.

## 1. Install

Install:

- Python 3.10 or newer from python.org.
- Icarus Verilog, so `iverilog` and `vvp` work in the terminal.
- VS Code extensions: Python and a Verilog/SystemVerilog extension.

No `pip install` is needed. The dashboard only uses built-in Python modules, especially `tkinter`.

Check Python GUI support:

```powershell
python -m tkinter
```

## 2. Test Dashboard Without Verilog

```powershell
python demo_stream.py | python edge_agri_dashboard.py
```

This should open the live dashboard with changing graphs, timestamp, actuator lamps, alerts, crop health, and SAFE/WARNING/CRITICAL status.

## 3. Add This To The Verilog Testbench

Print the CSV header once:

```verilog
initial begin
  $display("timestamp,moisture_raw,nutrient_raw,temp_raw,moisture_avg,nutrient_avg,temp_avg,pump_on,dose_nutrient,alert_nutrient,alert_weed,alert_heat,alert_frost,alert_anomaly,status,crop_health,relocate_recommend");
end
```

Print one row whenever the chip pipeline has a valid processed sample:

```verilog
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

Use numeric status:

- `0` = SAFE
- `1` = WARNING
- `2` = CRITICAL

## 4. Run With Real Simulation

Compile:

```powershell
iverilog -o simulation.vvp edge_analytics_top_tb.v edge_analytics_top.v sensor_collector.v moving_avg.v analytics_engine.v output_analytics.v
```

Run into dashboard:

```powershell
vvp simulation.vvp | python edge_agri_dashboard.py
```

## 5. Important

The dashboard can be built before the Verilog is finished. The only thing that must stay fixed is the CSV order. If the Verilog changes the order of fields, the dashboard graphs will show the wrong values.
