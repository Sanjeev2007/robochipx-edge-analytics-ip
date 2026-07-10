#!/usr/bin/env python3
"""Pure-Python VCD -> clean, slide-styled waveform SVG. No dependencies.
Renders digital bits as square waves and buses as gtkwave-style value hexagons."""
import re

VCD = "/Users/sanjeev/projects/Robochipx/edge_analytics/dump.vcd"

# ---------- parse ----------
name2sym = {}
with open(VCD) as f:
    lines = f.readlines()
for ln in lines:
    m = re.match(r"\$var\s+\w+\s+(\d+)\s+(\S+)\s+(\S+)(?:\s+\[[^\]]*\])?\s+\$end", ln)
    if m:
        name2sym[m.group(3)] = m.group(2)

def parse(signames):
    syms = {name2sym[n]: n for n in signames if n in name2sym}
    trans = {n: [] for n in signames if n in name2sym}
    t = 0
    for ln in lines:
        ln = ln.rstrip("\n")
        if not ln:
            continue
        c = ln[0]
        if c == "#":
            t = int(ln[1:]); continue
        if c in "01xz":
            sym = ln[1:]
            if sym in syms:
                trans[syms[sym]].append((t, ln[0]))
            continue
        if c == "b":
            p = ln.split()
            if len(p) == 2 and p[1] in syms:
                trans[syms[p[1]]].append((t, p[0][1:]))
            continue
    return trans

def val_at(tl, t):
    v = None
    for (tt, vv) in tl:
        if tt <= t:
            v = vv
        else:
            break
    return v

# ---------- format ----------
def fmt(v, kind):
    if v is None:
        return ""
    if "x" in v or "z" in v:
        return "x"
    if kind == "dec":
        return str(int(v, 2))
    if kind == "hex":
        n = int(v, 2)
        return "0x0" if n == 0 else f"0x{n:X}"
    if kind == "status":
        return {0: "SAFE", 1: "WARN", 2: "CRIT"}.get(int(v, 2), v)
    if kind == "bin":
        return v.lstrip("0") or "0"
    return v

# ---------- render ----------
def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

def render(rows, t0, t1, title, subtitle, out, annos=None, bands=None):
    """rows: list of (label, signame, kind) where kind in bit|dec|hex|status|bin|clk"""
    annos = annos or []
    bands = bands or []
    LBLW, ROWH, PLOTW = 190, 40, 1000
    PADT, PADL, PADR, PADB = 92, 18, 26, 44
    span = t1 - t0
    xs = PLOTW / span
    def X(t): return PADL + LBLW + (t - t0) * xs
    H = PADT + len(rows) * ROWH + PADB
    W = PADL + LBLW + PLOTW + PADR
    S = []
    S.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="Menlo,Consolas,monospace">')
    S.append(f'<rect width="{W}" height="{H}" fill="#0d1117"/>')
    # title
    S.append(f'<text x="{PADL}" y="30" fill="#e6edf3" font-size="21" font-weight="700" font-family="Helvetica,Arial">{esc(title)}</text>')
    S.append(f'<text x="{PADL}" y="52" fill="#8b98a5" font-size="13" font-family="Helvetica,Arial">{esc(subtitle)}</text>')
    plot_top = PADT
    plot_bot = PADT + len(rows) * ROWH
    # highlight bands
    for (ba, bb, col) in bands:
        S.append(f'<rect x="{X(ba):.1f}" y="{plot_top}" width="{(bb-ba)*xs:.1f}" height="{plot_bot-plot_top}" fill="{col}" opacity="0.14"/>')
    # clk gridlines (every 10ns rising edge)
    tick = 10000
    tg = (t0 // tick) * tick
    while tg <= t1:
        if tg >= t0:
            S.append(f'<line x1="{X(tg):.1f}" y1="{plot_top}" x2="{X(tg):.1f}" y2="{plot_bot}" stroke="#1c2530" stroke-width="1"/>')
        tg += tick
    parsed = parse([sn for (_, sn, _) in rows if sn])
    for i, (label, sn, kind) in enumerate(rows):
        yt = PADT + i * ROWH
        ymid = yt + ROWH / 2
        hi, lo = yt + 7, yt + ROWH - 9
        # row separator + label
        S.append(f'<line x1="{PADL+LBLW}" y1="{yt}" x2="{PADL+LBLW+PLOTW}" y2="{yt}" stroke="#161b22" stroke-width="1"/>')
        lblcol = "#f0b429" if kind == "hex" else ("#7ee787" if kind == "bit" else "#e6edf3")
        S.append(f'<text x="{PADL+LBLW-10}" y="{ymid+4:.1f}" fill="{lblcol}" font-size="13" text-anchor="end">{esc(label)}</text>')
        tl = parsed.get(sn, [])
        if kind in ("bit", "clk"):
            col = "#39d353"
            # build points
            v0 = val_at(tl, t0)
            cy = hi if (v0 == "1") else lo
            d = [f'M {X(t0):.1f} {cy:.1f}']
            pts = [(tt, vv) for (tt, vv) in tl if t0 < tt <= t1]
            cur = cy
            for (tt, vv) in pts:
                ny = hi if vv == "1" else lo
                d.append(f'L {X(tt):.1f} {cur:.1f} L {X(tt):.1f} {ny:.1f}')
                cur = ny
            d.append(f'L {X(t1):.1f} {cur:.1f}')
            S.append(f'<path d="{" ".join(d)}" fill="none" stroke="{col}" stroke-width="2"/>')
        else:
            # bus: hexagon segments with value text
            col = "#f0b429" if kind == "hex" else "#58a6ff"
            # collect change points within window
            changes = [t0] + [tt for (tt, vv) in tl if t0 < tt < t1] + [t1]
            segs = []
            for j in range(len(changes) - 1):
                segs.append((changes[j], changes[j + 1]))
            slew = min(6, span * xs * 0.004 / xs)  # small time slew
            slew = 3 / xs
            for (sa, sb) in segs:
                v = val_at(tl, sa)
                txt = fmt(v, kind)
                xa, xb = X(sa), X(sb)
                # hexagon: top & bottom lines with crossings at ends
                mid = ymid
                S.append(f'<path d="M {xa+3:.1f} {hi:.1f} L {xb-3:.1f} {hi:.1f}" stroke="{col}" stroke-width="1.6" fill="none"/>')
                S.append(f'<path d="M {xa+3:.1f} {lo:.1f} L {xb-3:.1f} {lo:.1f}" stroke="{col}" stroke-width="1.6" fill="none"/>')
                # left crossing
                S.append(f'<path d="M {xa:.1f} {mid:.1f} L {xa+3:.1f} {hi:.1f} M {xa:.1f} {mid:.1f} L {xa+3:.1f} {lo:.1f}" stroke="{col}" stroke-width="1.6" fill="none"/>')
                # text
                if (xb - xa) > 26 and txt:
                    S.append(f'<text x="{(xa+xb)/2:.1f}" y="{mid+4:.1f}" fill="#e6edf3" font-size="12" text-anchor="middle">{esc(txt)}</text>')
            # final right crossing
            S.append(f'<path d="M {X(t1):.1f} {ymid:.1f} L {X(t1)-3:.1f} {hi:.1f} M {X(t1):.1f} {ymid:.1f} L {X(t1)-3:.1f} {lo:.1f}" stroke="{col}" stroke-width="1.6" fill="none"/>')
    # bottom border
    S.append(f'<line x1="{PADL+LBLW}" y1="{plot_bot}" x2="{PADL+LBLW+PLOTW}" y2="{plot_bot}" stroke="#161b22" stroke-width="1"/>')
    # divider between labels and plot
    S.append(f'<line x1="{PADL+LBLW}" y1="{plot_top}" x2="{PADL+LBLW}" y2="{plot_bot}" stroke="#30363d" stroke-width="1.4"/>')
    # time axis
    tg = (t0 // tick) * tick
    ay = plot_bot + 16
    while tg <= t1:
        if tg >= t0:
            S.append(f'<line x1="{X(tg):.1f}" y1="{plot_bot}" x2="{X(tg):.1f}" y2="{plot_bot+5}" stroke="#8b98a5" stroke-width="1"/>')
            S.append(f'<text x="{X(tg):.1f}" y="{ay+4}" fill="#8b98a5" font-size="10" text-anchor="middle">{tg//1000}</text>')
        tg += tick * (2 if span > 120000 else 1)
    S.append(f'<text x="{PADL+LBLW+PLOTW}" y="{ay+22}" fill="#6a7581" font-size="11" text-anchor="end">time (ns) — 1 clk = 10 ns</text>')
    # annotations (vertical marker + callout)
    for (t, text, col) in annos:
        S.append(f'<line x1="{X(t):.1f}" y1="{plot_top-8}" x2="{X(t):.1f}" y2="{plot_bot}" stroke="{col}" stroke-width="1.4" stroke-dasharray="4 3"/>')
        S.append(f'<rect x="{X(t)+5:.1f}" y="{plot_top-24}" width="{7.0*len(text)+12:.0f}" height="19" rx="3" fill="{col}"/>')
        S.append(f'<text x="{X(t)+11:.1f}" y="{plot_top-10:.1f}" fill="#0d1117" font-size="12" font-weight="700" font-family="Helvetica,Arial">{esc(text)}</text>')
    S.append('</svg>')
    with open(out, "w") as f:
        f.write("\n".join(S))
    print("wrote", out)

# ================= Waveform A: Tier-2 anomaly -> radio =================
render(
    rows=[
        ("clk",              "clk",              "clk"),
        ("out_valid",        "out_valid",        "bit"),
        ("avg_temp",         "out_avg_temp",     "dec"),
        ("anom_ch[2:0]",     "out_anom_ch",      "bin"),
        ("alert_anomaly",    "out_alert_anomaly","bit"),
        ("msg_valid  → TX", "out_msg_valid","bit"),
        ("msg_count",        "out_msg_count",    "dec"),
        ("alert_packet",     "out_alert_packet", "hex"),
    ],
    t0=1995000, t1=2085000,
    title="Waveform 1 — TEDA anomaly → Tier-2 caretaker radio (event-triggered)",
    subtitle="The chip's self-tuning detector flags a channel, then transmits ONE 64-bit packet. This is the ~97%-fewer-TX moment.",
    out="/Users/sanjeev/projects/Robochipx/edge_analytics/synthesis/waveform_anomaly_radio.svg",
    bands=[(2025000, 2045000, "#f0b429")],
    annos=[(2025000, "TEDA flags ch", "#f85149"), (2035000, "radio TX", "#f0b429")],
)

# ================= Waveform B: Tier-1 pump hysteresis =================
render(
    rows=[
        ("clk",            "clk",             "clk"),
        ("out_valid",      "out_valid",       "bit"),
        ("moisture (raw)", "out_moisture",    "dec"),
        ("avg_moisture",   "out_avg_moisture","dec"),
        ("crop_health",    "out_crop_health", "dec"),
        ("status",         "out_status",      "status"),
        ("pump_on",        "out_pump_on",     "bit"),
    ],
    t0=385000, t1=515000,
    title="Waveform 2 — Tier-1 closed-loop: moisture smoothing → pump hysteresis (no human)",
    subtitle="Raw moisture is noisy; the divider-free moving average smooths it; the pump engages locally with hysteresis.",
    out="/Users/sanjeev/projects/Robochipx/edge_analytics/synthesis/waveform_pump_control.svg",
    annos=[(435000, "pump ON", "#39d353")],
)
