# EFLIM

Event-Based First-Photon FLIM: a self-supervised deep learning method for fluorescence lifetime
imaging microscopy (FLIM) under extreme low light (PPP < 1). Instead of building photon-count
histograms per pixel, EFLIM treats each excitation event as binary (photon / no photon) and uses
spatial-temporal context (a blind-spot denoising network) to estimate lifetime and intensity.

The repo has two independent stages that do **not** run in the same process:
1. **MATLAB (`spc2tiff/`)**: converts raw photon-counting hardware files into TIFF frame stacks.
2. **Python (root)**: trains a self-supervised denoiser per-dataset on those TIFF frames and
   produces denoised lifetime/intensity videos.

There is no live/online/streaming path — everything is **offline, file-based batch processing**.
Stage 1 processes a static `.spc` file with an interactive, manual-calibration workflow; stage 2
trains a fresh model from scratch on a folder of TIFF frames for N epochs before producing output.

## Setup on a new machine — GPU & CUDA notes

README covers the conda env + `pip install -r requirements.txt` steps adequately, but the
GPU/CUDA guidance there ("install PyTorch matching your CUDA via pytorch.org, e.g. cu118") is
thin on what actually happens at runtime. Verified against the code:

- **No pinned PyTorch/CUDA version anywhere in the repo** — `requirements.txt` deliberately
  excludes `torch`/`torchvision` and just says to install them separately. There is no lockfile,
  no CI, and no stated "tested with CUDA X.Y" anywhere, so the exact version used during
  development is undocumented. On a new machine, pick whatever PyTorch build matches the local
  CUDA toolkit via the official selector — there's no known-good pinned combination to replicate.
- **GPU is optional, not required.** `train.py:122` does `cuda = torch.cuda.is_available()`; if
  `False`, the model simply stays on CPU and skips `DataParallel` — it will run on a CPU-only
  machine, just without any documented speed expectation (nothing in the repo benchmarks
  CPU vs GPU throughput). Fine for a smoke-test/dry-run on a new PC before committing to GPU setup.
- **Multi-GPU is supported but only via `--gpu` as a comma list**, e.g. `--gpu 0,1,2`.
  `run_EFLIM.py:50-51` derives `args.ngpu` by counting commas in the `--gpu` string and sets
  `CUDA_VISIBLE_DEVICES` to it; `train.py:125` then wraps the model in
  `torch.nn.DataParallel(model, device_ids=range(args.ngpu))`. This is undocumented in the
  README — worth knowing before assuming a multi-GPU box needs extra flags.
- **Batch size is hardcoded to `1`** (`run_EFLIM.py:53`, `args.batch_size = 1`) regardless of GPU
  count or `--gpu` value — there is no CLI flag to change it. So VRAM sizing on a new machine is
  driven entirely by `--patch_size` (default `61 128 128`) and network width
  (`--unet_channels`, `--blind_conv_channels`, etc.), not by batch size. No VRAM requirement is
  documented anywhere in the repo — this has to be determined empirically per-GPU by starting
  with the default patch size and reducing it (or `--unet_channels`) on OOM.
- `spc2tiff.m` only needs base MATLAB (`Tiff` class in `saveastiff.m`) — no Image Processing
  Toolbox dependency found in `spc2tiff/utils/`.

**Net gap vs. README:** the CUDA installation instructions are fine, but a first-time setup on
a new PC should also know it can validate the pipeline on CPU first, that multi-GPU needs the
comma-list `--gpu` syntax, and that GPU memory is controlled by patch size / network width, not
batch size — none of which is in the README today.

## Stage 1 — Reading `.spc` files (`spc2tiff/spc2tiff.m`)

Input: a single Becker & Hickl `.spc` FIFO file (binary photon-stream format, e.g.
`spc2tiff/ExampleData/*.spc`, downloaded separately — not checked into the repo).

How it's parsed:
- The whole file is read via `fread(..., '*uint8')` and reinterpreted as a stream of `uint32`
  "events" (`typecast(alldata_8bit, 'uint32')`).
- Each 32-bit word is classified by its leading bits (via `dec2bin`):
  - `00...` = **photon event** — bits 5–16 give the 12-bit microtime (arrival time within one
    laser cycle, scaled by `unit_microT`), bits 20–32 give macrotime (coarse clock).
  - `01...` = **line marker** (scanner line-clock sync pulse).
  - `10000000...` = **macrotime overflow** (extends the macrotime counter by 4096 per event).
- This is a manual, multi-pass reconstruction pipeline, not a library-based decoder:
  1. Sample the first ~10,000 photons to build a microtime histogram and manually pick a timing
     `offset_ps` / `maxDetect_ps` / after-pulse threshold by eye (figure is plotted, values are
     hardcoded back into the script).
  2. Walk line markers to compute the line-clock interval.
  3. **First pass**: reconstruct ~300 frames while sweeping a scan-phase (`sph`) parameter,
     write out a multi-page TIFF of candidate alignments, and manually pick the correct `sph`
     from the saved image stack (`sph_array(233)` — a manually tuned index).
  4. **Second pass**: refine `macroT_start` similarly with a finer `sph` sweep (`sph_array(51)`).
  5. **Final pass**: replay the entire event stream once more, this time bucketing every photon
     into `(x, y, frame)` using the calibrated line/frame clocks and pixel dwell time, applying
     bidirectional-scan line-flipping correction, cropping to the requested capture size, and
     writing per-frame TIFFs plus summed intensity/fastFLIM (center-of-mass lifetime) images.
- Imaging geometry (frame size, frame rate, pixel dwell time, bi-directional scan, SPCM clock
  units) is supplied as MATLAB workspace variables at the top of the script, not CLI args.

Output of stage 1 (written under `spc2tiff/output/<timestamp>/`):
- `stack_ltframes_crop/frame_XXXXXX.tif` — per-frame photon arrival-time stacks (the actual
  training input for stage 2).
- `stack_photonNum_crop.tif`, `stack_lt_crop.tif` — summed intensity / fastFLIM (CMM lifetime)
  images per z-plane.
- `scanPhase.mat`, `scanPhase_residual.mat` — saved calibration parameters for reproducibility.

Because steps 3–4 require a human to look at a saved TIFF and hand-edit an index/offset in the
script before re-running, `spc2tiff.m` cannot be run unattended end-to-end — it's an interactive,
per-dataset calibration tool, reinforcing that this whole stage is offline preprocessing.

An alternative to real data: `0_simulations/run_simu_USAF1951.m` synthesizes photon-arrival TIFF
frames + ground-truth lifetime directly, skipping the `.spc` step entirely.

## Stage 2 — Training/inference (Python, entry point `run_EFLIM.py`)

Entry point: `python run_EFLIM.py --folderName <dir of per-frame .tif files>`. Also accepts
`--savepath`, `--gpu`, `--patch_size`, `--patch_interval`, `--n_epochs`, `--lr`, and network
hyperparameters (see `run_EFLIM.py:12-38`).

Flow:
- `FLIMDataset.addFrames_tiff` (`dataset.py`) loads every `.tif` frame in the folder into memory
  as photon arrival-time volumes, and extracts patches (`patch_size`/`patch_interval`, default
  61×128×128 with 10×64×64 stride) for a blind-spot self-supervised scheme (a target frame is
  predicted from surrounding frames only).
- Two identical-shaped models are trained independently, one after the other, both from
  `train.train()` in `train.py`:
  - `EFLIM` (`model.py`) for **lifetime** denoising — loss computed per-photon over all detected
    arrival times (`computeLoss`, feature='lifetime').
  - `SUPPORT` (`model.py`, architecture reused from the SUPPORT voltage-imaging denoiser) for
    **intensity** denoising.
- Training is a fixed number of epochs (`--n_epochs`, default 10) over the whole loaded dataset;
  by default only the last epoch is evaluated/saved (`--flag_testLastEpoch`), optionally every
  epoch (`--flag_testEachEpoch`). No online/incremental updates — this is standard offline
  supervised-on-self-blind-spots training, one full pass at a time.
- After both models finish, `inwlt()` (`utils.py`) composites the denoised lifetime + intensity
  into an RGB intensity-weighted lifetime visualization using a colormap `.mat` LUT from
  `0_simulations/utils/utils_lut/`.

Outputs (written to `--savepath`, default `<parent of folderName>/EFLIM/`):
- `model_lifetime_<epoch>.pth`, `model_intensity_<epoch>.pth` + matching optimizer state.
- `output_lifetime_<acq>_epoch<N>.tif`, `output_intensity_<acq>_epoch<N>.tif` — denoised stacks.
- `output_EFLIM_lt<lo>-<hi>_in<lo>-<hi>_<colormap>.tif` — final RGB intensity-weighted lifetime
  video (the headline deliverable).

## Bottom line on "real-time"

Nothing here is real-time. Stage 1 is a hand-calibrated, multi-pass offline converter for a
static `.spc` capture. Stage 2 loads an entire pre-converted TIFF folder into memory and trains
a fresh denoising model on it for a fixed number of epochs before writing results — there is no
streaming ingestion, no online inference loop, and no acquisition-time processing anywhere in
this codebase.
