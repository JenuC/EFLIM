# Getting Started on a New Machine

A step-by-step walkthrough to bring up EFLIM from scratch: environment → a fast CPU dry run on
synthetic data (so you learn the pipeline without waiting on a GPU or hunting for real `.spc`
data) → a real GPU run. See `CLAUDE.md` for the deeper explanation of how each stage works; this
file is just the ordered checklist.

Each step says what to run, what you should see if it worked, and why the step exists.

---

## 0. Prerequisites

- [ ] Python ≥ 3.9 available (via conda or system Python).
- [ ] MATLAB available — only needed for step 2 (generating synthetic data) and for converting
      real `.spc` files later. Base MATLAB is enough; no Image Processing Toolbox required
      (`spc2tiff/utils/utils_common/saveastiff.m` uses MATLAB's built-in `Tiff` class only).
- [ ] Do **not** worry about CUDA/GPU drivers yet — step 4 runs on CPU on purpose.

---

## 1. Create the Python environment

```bash
conda create -n eflim python=3.10 -y
conda activate eflim
pip install -r requirements.txt
```

**What this installs:** `numpy`, `scipy`, `tifffile`, `matplotlib`, `tqdm` — everything except
PyTorch, which is deliberately left out of `requirements.txt` so you can match it to whatever
CUDA (or no CUDA) is on this machine (see step 6).

**Check it worked:**
```bash
python -c "import numpy, scipy, tifffile, tqdm; print('ok')"
```

---

## 2. Install a CPU-only PyTorch (for the dry run)

We install a CPU build first on purpose — it lets you validate the entire training pipeline
(data loading → patching → model forward/backward → checkpoint/TIFF output) in a few minutes
without needing a working CUDA install yet. `EFLIM`'s training code auto-detects this:
`train.py:122` does `cuda = torch.cuda.is_available()` and silently trains on CPU when it's
`False` — no special flag needed.

```bash
pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
```

**Check it worked:**
```bash
python -c "import torch; print(torch.__version__); print('CUDA available:', torch.cuda.is_available())"
```
You should see `CUDA available: False` at this point — that's expected and correct for this step.

---

## 3. Generate a synthetic ground-truth dataset (MATLAB)

This sidesteps needing a real `.spc` file (which requires the manual calibration workflow
described in `CLAUDE.md`) and — importantly — gives you **known ground truth**, which real data
never does. Useful later if you want to quantify errors, not just eyeball TIFFs.

In MATLAB:
```matlab
run('0_simulations/run_simu_USAF1951.m')
```

**What this produces:** `./simu_USAF1951_PPP0.5/` containing:
- `raw/frame*.tif` — 500 synthetic photon-arrival frames at PPP = 0.5 (the actual training input)
- `lt_gt/lt_gt.tif` — the true lifetime map (ground truth, doesn't exist for real acquisitions)
- `lt_fastflim/lt_fastflim.tif` — the naive center-of-mass lifetime estimate (a baseline)

**Check it worked:** the `raw/` folder should contain ~500 `.tif` files.

---

## 4. CPU dry run

Run a single epoch on a small folder just to confirm the whole pipeline executes end-to-end —
this is the step that teaches you the shape of the pipeline (dataset loading, patch generation,
two-network training loop, RGB compositing) without burning GPU time.

```bash
python run_EFLIM.py \
  --folderName ./simu_USAF1951_PPP0.5/raw \
  --n_epochs 1
```

**What to watch for while it runs:**
- `Constructing a FLIMDataset` then `Loading TIFF files from ...` — confirms `dataset.py` found
  and loaded the 500 frames.
- A `tqdm` progress bar titled `Training lifetime 1/1` — this is training the `EFLIM` network
  (see `model.py`) using the masked per-photon loss described in `train.py:computeLoss`.
- A second `tqdm` bar titled `Training intensity 1/1` — this is the separate `SUPPORT` network.
- On CPU this will be slow per-batch but should still complete for 1 epoch on the default
  500-frame dataset in a reasonable time; if it's taking too long, cut it down further with
  `--patch_size 21 64 64 --patch_interval 5 32 32` to shrink patch volume.

**Check it worked:** `./simu_USAF1951_PPP0.5/EFLIM/` should now contain:
- `model_lifetime_0.pth`, `model_intensity_0.pth` (+ optimizer state files)
- `output_lifetime_0_epoch0.tif`, `output_intensity_0_epoch0.tif`
- `output_EFLIM_lt500-3500_in0-0.5_weddingdayblues.tif` — the final RGB visualization

Open that last file and `simu_USAF1951_PPP0.5/lt_gt/lt_gt.tif` side by side (e.g. in Fiji/ImageJ)
— after only 1 epoch the output will look rough, but the pipeline having run end-to-end without
errors is the point of this step.

---

## 5. Confirm your GPU / CUDA situation

Find out what's actually on this machine before choosing a PyTorch build:

```bash
nvidia-smi
```
Note the **CUDA Version** shown in the top-right of the output — that's the maximum CUDA
toolkit version your driver supports (not necessarily what you must install; PyTorch bundles its
own CUDA runtime).

---

## 6. Install the matching GPU build of PyTorch

Uninstall the CPU build and install the one matching your driver, using the
[official selector](https://pytorch.org/get-started/locally/). Example for CUDA 11.8:

```bash
pip uninstall torch torchvision -y
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu118
```

**Check it worked:**
```bash
python -c "import torch; print('CUDA available:', torch.cuda.is_available()); print(torch.cuda.get_device_name(0))"
```
You should now see `CUDA available: True` and your GPU's name.

Notes worth knowing before you scale up (see `CLAUDE.md` for details):
- **Batch size is hardcoded to 1** (`run_EFLIM.py:53`) — you cannot change it via CLI. GPU
  memory usage is controlled by `--patch_size` and network width flags
  (`--unet_channels`, `--blind_conv_channels`, etc.), not batch size.
- **Multi-GPU** needs a comma list: `--gpu 0,1,2` (drives `torch.nn.DataParallel`).
- No VRAM requirement is documented anywhere in the repo — if you hit an out-of-memory error,
  shrink `--patch_size` first.

---

## 7. Full GPU run

Now run with the defaults (or your own settings) for real:

```bash
python run_EFLIM.py \
  --folderName ./simu_USAF1951_PPP0.5/raw \
  --gpu 0
```

This uses the default `--n_epochs 10`, `--patch_size 61 128 128`, `--patch_interval 10 64 64`.
Outputs land in the same `./simu_USAF1951_PPP0.5/EFLIM/` folder as step 4, just further along in
training (higher epoch numbers, better quality).

---

## 8. (Optional) Try a real `.spc` file

Only once the synthetic pipeline above works end-to-end. This is a manual, interactive
calibration process (offset picking, scan-phase sweeps) — read the "Stage 1" section of
`CLAUDE.md` before starting, it is **not** a one-command conversion like the steps above.

---

## What you should understand after this walkthrough

- The two stages (`spc2tiff.m` → TIFF frames → `run_EFLIM.py`) are independent and file-based;
  nothing here is real-time (see `CLAUDE.md`).
- EFLIM trains two separate blind-spot networks (lifetime, intensity) from scratch per dataset,
  self-supervised via a temporal blind spot (`dataset.py:__getitem__` withholds the target frame).
- You now have one dataset (`simu_USAF1951_PPP0.5`) with actual ground truth
  (`lt_gt/lt_gt.tif`) — useful if you later want to quantify estimation error rather than just
  looking at the RGB output.
