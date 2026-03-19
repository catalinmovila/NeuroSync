# NeuroSync
# Multimodal Session Sync — FP · TTL · USV

A compact GUI for bringing **fiber photometry (FP)**, **behavioral logs (TTLBox)**, and **ultrasonic vocalizations (USVs)** onto a single, shared **session timeline**.

<p align="center">
  <img width="1000" alt="NeuroSync main interface" src="https://github.com/user-attachments/assets/8d5796ce-ccb2-425b-ba06-51d292379f41" />
</p>

## What’s in this repository
- **GUI entrypoint** for running the pipeline and inspecting results at session scale
- **Step-wise processing modules** (signal correction, synchronization, USV timeline shift)
- **Viewers** for full-session browsing + event inspection
- **Export utilities**

## Synchronization algorithm
**Affine Timebase Mapping (ATM)**

The synchronization workflow is based on an affine timebase mapping approach used to align session-level data streams recorded on different timelines.

<p align="center">
  <a href="https://docs.google.com/presentation/d/e/2PACX-1vQmRHWuTsihhUX6S6vKhXWTJFMvDaloy7AO2cZGQC3Fzdx6DR-IegAT9FSu5J55-Q/pub?start=false&loop=false&delayms=3000">
    <img src="images/atm_preview.png" alt="Affine Timebase Mapping presentation preview" width="1000">
  </a>
</p>

<p align="center">
  <em>Click the preview to open the full presentation.</em>
</p>

<p align="center">
  <a href="https://docs.google.com/presentation/d/e/2PACX-1vQmRHWuTsihhUX6S6vKhXWTJFMvDaloy7AO2cZGQC3Fzdx6DR-IegAT9FSu5J55-Q/pub?start=false&loop=false&delayms=3000">
    <img src="https://img.shields.io/badge/Open-Full%20Presentation-blue?style=for-the-badge" alt="Open Full Presentation">
  </a>
</p>
