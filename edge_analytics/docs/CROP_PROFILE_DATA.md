# Crop + Soil Profile Data — sourced agronomic setpoints for `crop_profile.v`

**Task:** DATA_TASKS.md Task 4 (judge-suggested per-crop/per-soil adaptation).
**Owner:** data-sourcing role · **Status:** delivered, ready for RTL lead to build `crop_profile.v`.

This file gives, for **4 crops × 3 soil textures**, the five ROM setpoints
`{moisture_target, nutrient_target, temp_lo, temp_hi, depletion_baseline}` in **real
agronomic units with a citation for every value**, then the **same values scaled to the
chip's 0–4095 raw range**, with every conversion shown so it is reproducible.

- **Crops (crop_id):** `0 = tomato` (warm, thirsty), `1 = wheat` (cool, staple),
  `2 = rice` (flooded), `3 = lettuce` (cool, shallow-root).
- **Soils (soil_id):** `0 = sandy`, `1 = loam`, `2 = clay`.

---

## 0. Scaling contract (per DATA_TASKS Task 4 / INTERFACES §3)

The chip works in 12-bit raw counts `0–4095`. Task 4 fixes the **full-range** mapping:

| Channel | Real range → count range | Count per unit | Inverse |
|---|---|---|---|
| moisture | 0–100 %VWC → 0–4095 | `count = %VWC × 40.95` | `%VWC = count / 40.95` |
| temperature | 0–50 °C → 0–4095 | `count = °C × 81.9` | `°C = count / 81.9` |
| nutrient | 0–1000 ppm → 0–4095 | `count = ppm × 4.095` | `ppm = count / 4.095` |

`40.95 = 4095/100`, `81.9 = 4095/50`, `4095/1000 = 4.095`. All scaled counts below are
`round(real × factor)`, and every one lands inside `0–4095`.

> ⚠️ **Encoding-reconciliation note for the RTL lead (read this).** The frozen §5
> thresholds and the canonical story-trace operate in a *compressed* band — the Phase-5.5
> testbench displays `moisture = count/5`, `temp = count/10` (INTERFACES §3 "Scaling
> formulas"), so its numbers live in **0–~500 counts** (`DRY=200 ≈ 40 %`, `HOT=400 ≈ 40 °C`).
> The Task-4 scaling above instead uses the **full 0–4095 range** (`40 % ≈ 1638`,
> `40 °C ≈ 3276`). These are two different fixed-point encodings of the same physics.
> **Before wiring the ROM,** decide which encoding `crop_profile.v` compares against:
> - If `crop_profile` outputs feed comparisons against the §5 thresholds / the story-trace
>   `avg_moisture`/`avg_temp` (the compressed band), divide the moisture counts by ~8.19
>   and the temp counts by ~1.638, **or** simply re-scale using `count = %VWC × 5` and
>   `count = °C × 10` (an "operational-band" column is given in §3a for exactly this).
> - If the pipeline is migrated to the full-range Task-4 encoding, use §2/§3 as-is.
> The real-unit table (§1) is encoding-independent and is the source of truth either way.

---

## 1. REAL-UNITS table (every value cited)

### 1a. Inputs pulled from the authoritative sources

**FAO-56 (Allen et al. 1998) — Table 12 (`Kc`) & Table 22 (rooting depth `Zr`, depletion `p`):**

| Crop | `Kc_mid` (T.12) | depletion `p` @ETc≈5 mm/d (T.22) | max root `Zr` (T.22) |
|---|---|---|---|
| tomato | 1.15 | **0.40** | 0.7–1.5 m |
| wheat (winter) | 1.15 | **0.55** | 1.5–1.8 m |
| rice | 1.20 | **0.20** | 0.5–1.0 m |
| lettuce | 1.00 | **0.30** | 0.3–0.5 m |

*Source: FAO Irrigation & Drainage Paper 56, Table 12 & Table 22 (fao.org/4/x0490e).*

**USDA NRCS — volumetric field capacity (FC), wilting point (WP), available water
capacity (AWC) by soil texture** (representative mid-points of the NRCS ranges):

| Soil | FC %VWC | WP %VWC | AWC = FC−WP |
|---|---|---|---|
| sandy | 20 | 7 | 13 % |
| loam | 40 | 12 | 28 % |
| clay | 50 | 18 | 32 % |

*Source: USDA NRCS "Soil Quality Indicators — Available Water Capacity" (sandy FC 15–25 %,
loam 35–45 %, clay 45–55 %; WP sandy 5–10 %, loam 10–15 %, clay 15–20 %). Sandy has the
smallest AWC → drains/depletes fastest; clay the largest buffer → slowest signal swing.*

**Agronomy cardinal temperatures (min / optimum / max, °C):**

| Crop | min | optimum | max | Source |
|---|---|---|---|---|
| tomato | 10 | 22–25 | 35 | greenhouse/agronomy cardinal-temp refs; physiological 18–27 °C |
| wheat | 4 | 20–25 (cited 25–31) | ~32–37 | Britannica cardinal-temp (min 0–5, opt 25–31, max 31–37 °C) |
| rice | 12–15 | 30–32 | 40 | rice grows 25–40 °C, opt 30–32 °C (agronomy refs) |
| lettuce | 7 | 16–18 | 27–28 | lettuce germ cardinal 7.9 / 23.3 / 28.0 °C; growth opt 18 °C (cool-season) |

**Extension soil-test NPK (land-grant guides):** the chip has ONE nutrient channel, so the
separate N-P-K soil-test critical levels below are aggregated into a single **available-NPK
fertility index (ppm)** per crop (see §1c). Cited critical/sufficiency levels:
- **Tomato** — UC IPM: apply P if soil-test P `< 15 ppm`, K if `< 150 ppm`; N sidedress when
  NO₃-N `< 15 ppm` (heavy feeder).
- **Wheat / small grains** — Tri-State & Missouri handbooks: P critical `15–30 ppm`, K
  optimum `120–170 ppm` (moderate feeder).
- **Rice** — maintenance P at Olsen-P `6–15 ppm`; K optimum `120–200 ppm` (moderate feeder).
- **Lettuce** — short-season light feeder; extension veg guides put it at the low end of the
  P `15–30 ppm` / K `120–150 ppm` sufficiency bands.

### 1b. Derived moisture setpoints (irrigation trigger)

`moisture_target` = the **irrigation-trigger** VWC = the point where readily-available water
is used up = `FC − p·(FC−WP) = FC − p·AWC` (FAO-56 allowable-depletion definition). Soil
texture shifts it (via FC/WP/AWC); crop shifts it (via `p`).

| Crop \ Soil | sandy (FC20,AWC13) | loam (FC40,AWC28) | clay (FC50,AWC32) |
|---|---|---|---|
| tomato (p=0.40) | 20−0.40·13 = **14.8 %** | 40−0.40·28 = **28.8 %** | 50−0.40·32 = **37.2 %** |
| wheat (p=0.55) | 20−0.55·13 = **12.9 %** | 40−0.55·28 = **24.6 %** | 50−0.55·32 = **32.4 %** |
| rice (p=0.20) | 20−0.20·13 = **17.4 %** | 40−0.20·28 = **34.4 %** | 50−0.20·32 = **43.6 %** |
| lettuce (p=0.30) | 20−0.30·13 = **16.1 %** | 40−0.30·28 = **31.6 %** | 50−0.30·32 = **40.4 %** |

Reads correctly: wheat tolerates the deepest depletion (p=0.55 → lowest trigger); rice the
shallowest (p=0.20 → keep it wet, near flooded); clay always triggers at a higher %VWC than
sandy because it holds more water at every tension.

### 1c. Nutrient index and depletion baseline

**`nutrient_target` (available-NPK fertility index, ppm)** — a single-channel proxy that
preserves the *relative* feeding demand of each crop (component soil-test levels are cited in
§1a; the crop-normalized index magnitude is **ESTIMATED / design-calibrated** so it sits
above the frozen `NUT_THRESH`):

| Crop | index ppm | rationale (cited components) |
|---|---|---|
| tomato | 95 | heavy feeder (UC IPM K-suff 150 ppm, high N demand) |
| rice | 85 | moderate-heavy (K opt 120–200 ppm) |
| wheat | 75 | moderate (P 15–30, K 120–170 ppm) |
| lettuce | 70 | light, short-season (low end of suff. bands) |

*Soil note: sandy soils leach N/K fastest → replenish more often (reflected in the depletion
baseline, not the target level). Nutrient target is crop-driven, soil-independent.*

**`depletion_baseline` (expected NORMAL moisture drop, %VWC per sample)** — the healthy
drying rate, used so the weed detector isn't fooled by fast-draining soil. Reproducible
formula: `drop%/sample = Kc_mid · C / AWC_fraction`, with design constant `C = 0.12`
(calibrates loam-tomato to ≈0.5 %/sample). Grounded in cited `Kc` (FAO-56) and `AWC` (USDA);
the constant `C` is **ESTIMATED**. Fast for sandy (small AWC), slow for clay (large AWC):

| Crop \ Soil | sandy | loam | clay |
|---|---|---|---|
| tomato (Kc1.15) | 1.06 %/s | 0.49 %/s | 0.43 %/s |
| wheat (Kc1.15) | 1.06 %/s | 0.49 %/s | 0.43 %/s |
| rice (Kc1.20) | 1.11 %/s | 0.51 %/s | 0.45 %/s |
| lettuce (Kc1.00) | 0.92 %/s | 0.43 %/s | 0.38 %/s |

---

## 2. SCALED table (chip units, 0–4095) — full-range Task-4 encoding

Conversions applied: moisture `%×40.95`, temp `°C×81.9`, nutrient `ppm×4.095`,
depletion `%/sample × 40.95`. Values `round()`-ed.

### moisture_target (irrigation trigger), counts
| Crop \ Soil | sandy | loam | clay | conversion (loam shown) |
|---|---|---|---|---|
| tomato | 606 | 1179 | 1523 | 28.8×40.95 = 1179 |
| wheat | 526 | 1007 | 1327 | 24.6×40.95 = 1007 |
| rice | 713 | 1409 | 1785 | 34.4×40.95 = 1409 |
| lettuce | 659 | 1294 | 1654 | 31.6×40.95 = 1294 |

### nutrient_target, counts (soil-independent)
| Crop | ppm | count | conversion |
|---|---|---|---|
| tomato | 95 | 389 | 95×4.095 = 389.0 |
| wheat | 75 | 307 | 75×4.095 = 307.1 |
| rice | 85 | 348 | 85×4.095 = 348.1 |
| lettuce | 70 | 287 | 70×4.095 = 286.7 |

### temp_lo / temp_hi, counts (soil-independent)
| Crop | lo °C | lo count | hi °C | hi count | conversion |
|---|---|---|---|---|---|
| tomato | 10 | 819 | 35 | 2867 | 10×81.9=819 · 35×81.9=2866.5 |
| wheat | 4 | 328 | 32 | 2621 | 4×81.9=327.6 · 32×81.9=2620.8 |
| rice | 15 | 1229 | 38 | 3112 | 15×81.9=1228.5 · 38×81.9=3112.2 |
| lettuce | 7 | 573 | 27 | 2211 | 7×81.9=573.3 · 27×81.9=2211.3 |

### depletion_baseline, counts per sample
| Crop \ Soil | sandy | loam | clay | conversion (sandy tomato) |
|---|---|---|---|---|
| tomato | 43 | 20 | 18 | 1.06×40.95 = 43.4 |
| wheat | 43 | 20 | 18 | — |
| rice | 45 | 21 | 18 | 1.11×40.95 = 45.5 |
| lettuce | 38 | 18 | 15 | 0.92×40.95 = 37.7 |

### 3a. (Optional) operational-band equivalents — for the §5 threshold encoding
If `crop_profile.v` must sit *next to* the frozen §5 thresholds (`DRY=200`, `HOT=400` in the
compressed testbench band), use `moisture count = %×5`, `temp count = °C×10` instead. E.g.
tomato-loam trigger `28.8×5 = 144`, tomato temp_hi `35×10 = 350`, depletion tomato-sandy
`1.06×5 = 5/sample`. Same physics, compressed encoding. Pick ONE encoding project-wide.

---

## 3. ROM-ready block (full-range Task-4 encoding)

For each `{crop_id, soil_id}`, the 5 scaled integers in fixed order
`{moisture_target, nutrient_target, temp_lo, temp_hi, depletion_baseline}`:

```
# crop_id 0 = tomato
{0,0} sandy : { 606, 389,  819, 2867, 43 }
{0,1} loam  : {1179, 389,  819, 2867, 20 }
{0,2} clay  : {1523, 389,  819, 2867, 18 }
# crop_id 1 = wheat
{1,0} sandy : { 526, 307,  328, 2621, 43 }
{1,1} loam  : {1007, 307,  328, 2621, 20 }
{1,2} clay  : {1327, 307,  328, 2621, 18 }
# crop_id 2 = rice
{2,0} sandy : { 713, 348, 1229, 3112, 45 }
{2,1} loam  : {1409, 348, 1229, 3112, 21 }
{2,2} clay  : {1785, 348, 1229, 3112, 18 }
# crop_id 3 = lettuce
{3,0} sandy : { 659, 287,  573, 2211, 38 }
{3,1} loam  : {1294, 287,  573, 2211, 18 }
{3,2} clay  : {1654, 287,  573, 2211, 15 }
```

Flat init order (crop-major, soil-minor) for a `reg [W-1:0] rom [0:11]`-style lookup —
address = `crop_id*3 + soil_id`. `nutrient_target`, `temp_lo`, `temp_hi` repeat across soils
(crop-driven); `moisture_target` and `depletion_baseline` vary with soil (texture-driven).

---

## 4. SOURCES (References slide)

1. **Allen, R.G., Pereira, L.S., Raes, D., Smith, M. (1998).** *Crop Evapotranspiration —
   Guidelines for computing crop water requirements.* FAO Irrigation & Drainage Paper 56.
   FAO, Rome. — **Table 12** (single crop coefficient `Kc`), **Table 22** (max rooting depth
   `Zr` and soil-water depletion fraction `p`). https://www.fao.org/4/x0490e/x0490e0b.htm
   (Ch.6, Table 12) · https://www.fao.org/4/x0490e/x0490e0e.htm (Ch.8, Table 22).
2. **USDA NRCS.** *Soil Quality Indicators — Available Water Capacity.* Field capacity,
   wilting point, and AWC by soil texture (sandy / loam / clay).
   https://www.nrcs.usda.gov/sites/default/files/2022-10/nrcs142p2_051590.pdf
3. **UC IPM / UC ANR.** *Fertilization — Tomato (soil-test N-P-K guidelines).*
   https://ipm.ucanr.edu/agriculture/tomato/fertilization/
4. **Tri-State Fertilizer Recommendations (OSU/MSU/Purdue) & University of Missouri Soil Test
   Interpretations Handbook.** P/K critical & optimum soil-test levels for field crops
   (wheat, small grains). https://ohioline.osu.edu/factsheet/agf-0515 ·
   http://aes.missouri.edu/pfcs/soiltest.pdf
5. **Rice P & K management** (extension "Specialists Speaking", *Rice Farming*), Olsen-P
   maintenance range and K optimum. https://www.ricefarming.com/departments/specialists-speaking/p-and-k-management/
6. **Agronomy cardinal-temperature references** — crop min/optimum/max growth temperatures
   (tomato, wheat, rice, lettuce). Encyclopædia Britannica "cardinal temperature"; greenhouse
   cardinal-temperature tables; lettuce germination cardinal-temperature study (bilinear
   7.9 / 23.3 / 28.0 °C). https://www.britannica.com/topic/cardinal-temperature

**Values marked ESTIMATED** (not directly sourced): the single-channel `nutrient_target`
index magnitude (component N-P-K soil-test levels ARE cited; only their aggregation into one
0–1000 ppm index is design-normalized) and the depletion-baseline design constant `C=0.12`
(the `Kc`/`AWC` it is built on ARE cited). No citations were invented for these.
