# PadViz8 — a quick guide to playing with the paddle data

Thanks for taking a look. This is a small viewer for data from two motion sensors —
one on a kayak paddle, one on the boat — plus GPS. You don't need to install
anything except **Processing** (free). It should take about five minutes to get
going. Follow the steps in order.

---

## 1. Install Processing (one time)

1. Go to **https://processing.org/download**
2. Download **Processing 4** for your operating system (Windows / macOS / Linux).
3. Unzip / install it and open the **Processing** application.

Nothing else to install — the viewer uses only Processing's built-in features.

---

## 2. Put the files in the right place

You've been sent two folders. **They must sit next to each other in the same
parent folder**, like this:

```
some-folder/
├── PadViz8/                       ← the viewer (the "sketch")
│   ├── PadViz8.pde
│   └── … (lots of other files)
└── recordings/                    ← the data — put the 3 files here
    ├── PadLog20260830.CSV         ← paddle sensor
    ├── BoatLog20260830.CSV        ← boat sensor + GPS
    └── PadLog20260830.session.json ← the "session" file (calibration etc.)
```

The important bit: **`PadViz8` and `recordings` are side by side**, and the three
data files go **inside `recordings`**. If that layout is right, everything else is
automatic.

---

## 3. Open and run the viewer

1. In Processing: **File → Open…**, browse to the **`PadViz8`** folder, and open
   **`PadViz8.pde`**.
2. Press the **▶ Run** button (top-left of the Processing window) — or
   **Ctrl+R** (Windows/Linux) / **Cmd+R** (Mac).
3. A new window opens showing a short setup screen. That's expected.

---

## 4. Load the data — just one key

Press **`J`**.

A file chooser opens (in the `recordings` folder). Pick
**`PadLog20260830.session.json`**.

That's the whole load step. It pulls in the paddle data, the boat data, and my
calibration in one go, and drops you straight into the 3D view. You do **not** need
to load the CSVs separately — the session file points to them.

> If pressing `J` does nothing: the `recordings` folder isn't sitting next to the
> `PadViz8` folder, or the `.session.json` isn't inside it. Fix the layout in
> step 2 and re-run.

---

## 5. The one key to press: **`Y`**

You'll be looking at **Slice C** — the paddle and the kayak together in 3D. (If in
doubt, press **`3`** to make sure you're in Slice C. Please stay in Slice C for
this — the other slices aren't needed.)

Now press **`Y`**.

This is the interesting toggle. It switches which of the two orientation methods the
viewer uses:

- One method makes the paddle look **~45° twisted and oddly flat** (as if it isn't
  rolling about its own shaft).
- Pressing **`Y`** switches to the other method, which **squares the paddle up and
  restores the natural roll** about the shaft — the correct picture.

Press **`Y`** again to flip back and forth and see the difference. This is the main
thing I'd like your eye on.

**Moving the view around:**
- **Left-click and drag** — rotate (orbit) the scene.
- **Scroll wheel** — zoom in/out.
- **`v`** — reset the camera to a standard angle.
- **Spacebar** — play / pause the stroke animation.
- Or **click and drag along the graph** at the bottom to scrub through time by hand.

---

## 6. Flip between the three windows

There are three full-screen views. Switch between them with single keys (or click the
tabs at the top-right). You start in the 3D view.

| Key | Window | What it shows |
|----|--------|---------------|
| *(start)* | **3D view** (Slice C) | The paddle and kayak in 3D, driven by the sensors — watch the paddle move relative to the boat through each stroke. This is where you press `Y`. |
| **`x`** | **Side profile** | Two side-on views of the kayak with the blade drawn in the water — how deep and where along the hull each blade works. A coloured band builds up along the hull showing the part of the blade that was underwater. Press **`x`** again to return to 3D. |
| **`t`** | **Track map** | The GPS track of the outing drawn over a street map (OpenStreetMap). Needs internet the **first** time, to fetch the map tiles. Press **`t`** again to return to 3D. |

That's everything — load with `J`, sit in Slice C, press `Y` a few times, and flip
between the three windows with `x` and `t`. Thanks for looking!

---

*Tip: if the paddle ever looks 45° off or unnaturally flat, press `Y`. If the map is
blank, check you're online and give it a few seconds to download tiles.*
