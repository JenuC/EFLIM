# FLIMD Repository Summary

**Generated:** 2026-07-20  
**Repository:** FLIMD - Unsupervised FLIM Data Denoising using Deep Learning  
**Author:** Bin Li (Eliceiri Lab/LOCI)  
**Version:** 0.1.0

---

## Overview

FLIMD is a Python library for unsupervised Fluorescence Lifetime Imaging Microscopy (FLIM) data denoising using deep neural networks. The library implements a self-supervised denoising approach based on PyTorch.

---

## Repository Structure

### Core Package (`flimd/`)

The main Python package containing the deep learning denoising implementation:

#### `__init__.py`
- Package initialization file
- Version: 0.1.0
- Author: Bin Li
- Credits: Eliceiri Lab/LOCI

#### `denoiser.py`
- **Main denoising class**: `Denoiser`
- Implements self-supervised FLIM denoising using neural networks
- Supports 1D, 2D, and 3D convolutional models
- Key features:
  - Model dimension selection (1D/2D/3D convolutions)
  - Configurable model depth and base channels
  - GPU/CPU support
  - Loss functions: MSE and Lifetime-Regularized (LTR)
  - Rolling/sliding window for timelapse datasets
  - Dropout-based self-supervised training

#### `flim_datasets.py`
- **PyTorch Dataset class**: `FLIM_Dataset`
- Loads FLIM data from CSV file manifests
- Data augmentation transforms for 3D data:
  - `Rotate3D`: Random 90° rotations
  - `Flip3D`: Random horizontal/vertical flips
  - `ToTensor3D`: Converts numpy arrays to PyTorch tensors
- Handles normalization and intensity rescaling
- Supports configurable spatial dimensions (default 256x256)

#### `preprocessor.py`
- **Preprocessing class**: `FLIMPreprocessor`
- Data preparation and compression utilities
- Key functions:
  - `compress_h5()`: Compress TIFF images into HDF5 format
  - `generate_csv()`: Create dataset manifests
  - `calculate_norm_range()`: Compute normalization parameters
  - `generate_compress_csv()`: Combined compress and manifest generation
  - `subsample()`: Create training subsets
  - `split_train_val()`: Generate train/validation splits

#### `model_blender.py`
- Neural network architectures for spatial denoising
- **Classes:**
  - `Blender3D`: 3D convolutional blending network
  - `Blender2D`: 2D convolutional blending network
  - `Distributor`: Latent space distribution layer
  - `Model`: Combined distributor + blender architecture
- Features residual connections and optional deep blending
- Supports configurable base channels and depth

#### `lifetime_regularized_loss.py`
- **Custom loss function**: `LTRegularizedLoss`
- Lifetime-regularized loss for FLIM data
- Weights loss by:
  - Photon counts (brighter pixels get more weight)
  - Temporal bin intensity distribution
  - Dynamic normalization factors
- Helps preserve lifetime information during denoising

---

### Configuration Files

#### `setup.py`
- Package installation configuration
- Dependencies:
  - numpy >= 1.17
  - PyTorch and torchvision >= 0.2
  - matplotlib >= 3.1
  - scikit-learn >= 0.21, scikit-image >= 0.16
  - pyyaml >= 5.2, pandas >= 1.1
  - tqdm >= 4.50, imageio >= 2.8, h5py >= 2.1
- Python >= 3.6 required
- CUDA 10.2 or 11.1 supported

#### `env.yml`
- Conda environment specification
- Environment name: `denoising`
- Channels: pytorch, anaconda, conda-forge
- Includes JupyterLab for notebook development

#### `.gitignore`
- Excludes:
  - Python bytecode (*.pyc)
  - Jupyter checkpoints
  - `datasets/` directory
  - Build artifacts (build/, dist/, *.egg-info)
  - Output directories (output_1_1D/)
  - CSV files (df_simulation.csv)

---

### Documentation & Analysis

#### `README.md`
- Installation instructions using conda
- PyTorch installation guide (tested with 1.8.2)
- Quick start: Points to `Quick Start.ipynb`
- Advanced usage: References `Main.ipynb`

#### `NOTEBOOK_ANALYSIS.md`
- Comprehensive analysis of all 31 Jupyter notebooks
- Dataset usage matrix
- Notebook categorization (demo, experiment, analysis, figure, test)
- Consolidation recommendations
- Identifies:
  - 9 unique datasets
  - TMA dataset most used (11 notebooks)
  - 42k dataset in 8 notebooks
  - Multiple notebooks with similar purposes

#### `analyze_notebooks.py`
- Automated notebook analysis script
- **Classes:**
  - `NotebookScanner`: Finds and parses Jupyter notebooks
  - `DatasetExtractor`: Identifies datasets used in notebooks
  - `PurposeInferencer`: Infers notebook purpose from content
  - `ReportGenerator`: Generates markdown analysis reports
- Analyzes:
  - Imports and dependencies
  - Dataset references
  - Notebook categories and purposes
  - Code patterns and functions used
- Generates consolidation recommendations

---

### Data Files

#### `truth/`
- Contains ground truth data: `TMACORE1_009_.tif`
- Reference/validation data for testing

---

## Jupyter Notebooks

### Demo Notebooks (4 total)

#### `Quick Start.ipynb`
- **Purpose:** Simple demo for quick start
- **Datasets:** 42k, H2B, TMA
- Recommended entry point for new users

#### `Quick Start-simulations.ipynb`
- **Purpose:** Simulation testing demo
- **Datasets:** 42k
- Introduction to simulation-based validation

#### `Main.ipynb`
- **Purpose:** Advanced denoising demonstration
- **Datasets:** TMA, Wei_SPAD
- More complex customization examples

#### `quick_tests_to_del.ipynb`
- **Purpose:** Quick tests (marked for deletion)
- **Datasets:** 42k, TMA, apoptosis
- **Status:** Temporary/testing notebook

---

### Analysis Notebooks (6 total)

#### `A_compare_1D_3D_median_gaussian.ipynb`
- **Purpose:** Comparative analysis of 1D vs 3D models
- **Datasets:** TMA
- Compares different denoising approaches

#### `A_multilevel.ipynb`
- **Purpose:** Multilevel FLIM fitting
- **Datasets:** TMA

#### `B_300TMA.ipynb`
- **Purpose:** FLIM fitting on 300 TMA cores
- **Datasets:** TMA

#### `FLIM Fitting.ipynb`
- **Purpose:** FLIM fitting procedures
- **Datasets:** TMA

#### `Preprocessing.ipynb`
- **Purpose:** Data preprocessing workflows
- **Datasets:** 42k, H2B

#### `E_42kdataset.ipynb`
- **Purpose:** Comparative analysis across datasets
- **Datasets:** 42k, BB, TMA, apoptosis

---

### Experiment Notebooks (15 total)

#### 2022 Experiments (7 notebooks)
- `20220105_roll_vs_chunk_42kdataset.ipynb` - Rolling vs chunking comparison (42k)
- `20220204_2compRLD_42k_data.ipynb` - Two-component RLD fitting (42k)
- `20220510_simulation_simplified.ipynb` - Simplified simulations (BB, GZ, TMA, simulated)
- `20220515_plots_remake_lost_date.ipynb` - Figure remake (simulated)
- `20220628_biexp_simulations_clean.ipynb` - Biexponential simulations (simulated)
- `20221110_H2B_dataset_.ipynb` - H2B dataset analysis
- `20221221_blockmatching_repeats.ipynb` - Block matching experiments (TMA)

#### 2023 Experiments (8 notebooks)
- `20230620_brian_microglia_data.ipynb` - Microglia denoising (BB)
- `20230729_BBdata.ipynb` - BB dataset fitting (microglia)
- `20230731_GZdata_catalog.ipynb` - GZ data cataloging
- `20230801_Gz_tracking.ipynb` - GZ tracking analysis
- `20230802_GZdata.ipynb` - GZ data fitting (GZ, microglia)
- `20230804_BBdata_ch_refit.ipynb` - BB channel refitting (microglia)
- `20230808_guhanCleandataCompile.ipynb` - Data compilation
- `20231205_wei_Spad_data.ipynb` - Wei SPAD data denoising

#### Lettered Experiments
- `A_simulated.ipynb` - Simulation testing (BB, simulated)

---

### Figure Generation Notebooks (3 total)

#### `F_Apoptosis_plots.ipynb`
- **Purpose:** Apoptosis figure generation
- **Datasets:** apoptosis

#### `_figures_compilation.ipynb`
- **Purpose:** Comprehensive figure compilation
- **Datasets:** 42k, BB, H2B, simulated

#### `20220515_plots_remake_lost_date.ipynb`
- **Purpose:** Recreating lost plots
- **Datasets:** simulated

---

### Test Notebooks (3 total)

#### `C_Test_train_Performance.ipynb`
- **Purpose:** Testing train/test performance
- **Datasets:** TMA
- **Status:** Test notebook

#### `Fc_check_seg2.ipynb`
- **Purpose:** Segmentation checking
- **Datasets:** apoptosis
- **Status:** Test notebook

#### `test_data.ipynb`
- **Purpose:** Data testing
- **Datasets:** None
- **Status:** Test notebook

---

## Datasets Used

### Primary Datasets (by usage count)

1. **TMA (Tissue Microarray)** - 11 notebooks
   - Most extensively used dataset
   - 300 TMA cores analyzed in B_300TMA.ipynb

2. **42k Dataset** - 8 notebooks
   - Also referenced as HV65k
   - Large-scale FLIM dataset

3. **BB (Brian) Dataset** - 5 notebooks
   - Microglia FLIM data
   - Multiple fitting experiments

4. **Simulated Data** - 5 notebooks
   - For validation and method testing
   - Biexponential simulations

5. **GZ (Guhan) Dataset** - 4 notebooks
   - Includes tracking analysis
   - Data cataloging

6. **H2B Dataset** - 4 notebooks
   - Dedicated analysis notebook (20221110)

7. **Apoptosis Dataset** - 4 notebooks
   - Figure generation focus

8. **Microglia Dataset** - 3 notebooks
   - Related to BB dataset

9. **Wei_SPAD Dataset** - 2 notebooks
   - SPAD detector data

---

## Development Timeline

### Git History (Recent Commits)
- **2024-12:** Changes from figure compilation (analysis branch)
- **2023-12:** Major updates
- **2023-08:** All files added after Aug 18
- **2023-03:** Cleanup before India trip
- Previous work includes:
  - PyWidgets GUI addition
  - Helen's data interpretation
  - Heterogeneity characterization
  - Block matching tests

---

## Key Features

### Denoising Capabilities
- **Self-supervised learning**: No ground truth required
- **Multi-dimensional models**: 1D, 2D, and 3D convolutions
- **Flexible architecture**: Configurable depth and channels
- **Custom loss functions**: MSE and lifetime-regularized
- **Data augmentation**: Rotations, flips for 3D data
- **GPU acceleration**: CUDA support

### Data Processing
- **HDF5 compression**: Efficient storage of TIFF stacks
- **Normalization**: Automatic intensity range calculation
- **Train/validation splits**: Built-in dataset splitting
- **Subsampling**: Memory-efficient training on large datasets

### Analysis Tools
- **Automated notebook scanning**: Identifies datasets and purposes
- **Usage tracking**: Dataset usage matrix
- **Consolidation recommendations**: Identifies redundant analyses

---

## Installation & Usage

### Installation Steps
1. Install Anaconda/Miniconda
2. Create environment: `conda env create --name denoising --file env.yml`
3. Activate: `conda activate denoising`
4. Install PyTorch 1.8.2 with CUDA support (if available)

### Quick Start
1. Begin with `Quick Start.ipynb` for basic usage
2. Explore `Main.ipynb` for advanced customization
3. Check `Preprocessing.ipynb` for data preparation

---

## Recommendations for Repository Maintenance

### High Priority
1. **Delete test notebooks**: `C_Test_train_Performance.ipynb`, `Fc_check_seg2.ipynb`, `test_data.ipynb`, `quick_tests_to_del.ipynb`
2. **Consolidate FLIM fitting**: Merge 10 fitting notebooks into 2-3 organized by dataset
3. **Consolidate simulations**: Merge 5 simulation notebooks into single comprehensive notebook

### Medium Priority
1. Review 2022 notebooks (7 total) for relevance
2. Archive superseded experiments
3. Create comprehensive documentation notebook

### Low Priority
1. Update README with more detailed examples
2. Add API documentation for flimd package
3. Create contributing guidelines

---

## Technical Specifications

### Python Package Structure
```
flimd/
├── __init__.py                      # Package initialization
├── denoiser.py                      # Main Denoiser class
├── flim_datasets.py                 # PyTorch Dataset classes
├── preprocessor.py                  # Data preprocessing utilities
├── model_blender.py                 # Neural network architectures
└── lifetime_regularized_loss.py    # Custom loss functions
```

### Dependencies Summary
- **Core**: PyTorch, NumPy
- **Image Processing**: scikit-image, imageio, Pillow
- **Data**: pandas, h5py, PyYAML
- **Visualization**: matplotlib
- **ML**: scikit-learn
- **UI**: tqdm (progress bars), jupyterlab

### Hardware Requirements
- **Minimum**: CPU with 8GB RAM
- **Recommended**: NVIDIA GPU with CUDA 10.2+ and 16GB+ RAM
- **Storage**: Depends on dataset size (HDF5 compression reduces requirements)

---

## Repository Statistics

- **Total Notebooks**: 31
- **Total Python Files**: 8 (7 in package + 1 utility)
- **Unique Datasets**: 9
- **Active Development Branch**: analysis
- **Package Version**: 0.1.0
- **License**: MIT License

---

## Contact Information

- **Author**: Bin Li
- **Email**: bli346@wisc.edu
- **Lab**: Eliceiri Lab/LOCI
- **Repository**: https://github.com/binli123/stochastic-flim-denoising

---

*This summary was automatically generated from repository contents on 2026-07-20.*
