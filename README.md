# NeuroSync
# Multimodal Session Sync — FP · TTL · USV

A compact toolbox + GUI for bringing **fiber photometry (FP)**, **behavioral TTL logs (TTLBox)**, and **ultrasonic vocalizations (USVs)** onto a single, shared **session timeline**.

<img width="1920" height="1017" alt="APPMENU" src="https://github.com/user-attachments/assets/8d5796ce-ccb2-425b-ba06-51d292379f41" />


## What’s in this repository
- **GUI entrypoint** for running the pipeline and inspecting results at session scale
- **Step-wise processing modules** (signal correction, synchronization, USV timeline shift)
- **Viewers** for fast QC: full-session browsing + event-centered inspection windows
- **Export utilities** for analysis-ready tables (alignment, mapping, event summaries)

## What it does
- Decodes TTLBox pulses and detects TTL edges from the audio-encoded TTL WAV
- Computes a stable mapping between independent timebases (audio ↔ TTLBox)
- Applies the mapping to shift USV call times onto the TTLBox session clock
- Produces synchronized overlays for inspection and structured exports for downstream stats/figures

## Synchronization algorithm
**Affine Timebase Mapping (ATM)**  
Timebase relationship is modeled as:

**t_TTLBox = a · t_audio + b**

Estimated via:
1) **coarse offset search** (histogram of time differences)  
2) **tolerance-based greedy matching** of candidate events  
3) **linear fit** to obtain *(a, b)* and residual QC metrics

## Key outputs (exports)
- `*_TTLBox_EVENTS.xlsx` — decoded pulses + counts  
- `*_WAV_vs_TTLBox_ALIGNMENT.xlsx` — matched events across timebases  
- `*_SYNC_MAPPING.xlsx` — mapping parameters *(a, b)* used for shifting USVs

## Code layout
- `FP_TTL_USV_MasterApp.m` — main application entrypoint
- `core/` — helpers + safe IO utilities
- `steps/` — pipeline steps (correction, sync mapping, applying shifts)
- `viewers/` — timeline viewers and QC tools

