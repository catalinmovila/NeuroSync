# NeuroSync
# Multimodal Session Sync — FP · TTL · USV

A compact GUI for bringing **fiber photometry (FP)**, **behavioral logs (TTLBox)**, and **ultrasonic vocalizations (USVs)** onto a single, shared **session timeline**.

<img width="1920" height="1017" alt="APPMENU" src="https://github.com/user-attachments/assets/8d5796ce-ccb2-425b-ba06-51d292379f41" />


## What’s in this repository
- **GUI entrypoint** for running the pipeline and inspecting results at session scale
- **Step-wise processing modules** (signal correction, synchronization, USV timeline shift)
- **Viewers** for full-session browsing + event inspection
- **Export utilities** 

## Synchronization algorithm
**Affine Timebase Mapping (ATM)**  


<iframe src="https://docs.google.com/presentation/d/e/2PACX-1vQmRHWuTsihhUX6S6vKhXWTJFMvDaloy7AO2cZGQC3Fzdx6DR-IegAT9FSu5J55-Q/pubembed?start=false&loop=false&delayms=5000" frameborder="0" width="1920" height="1109" allowfullscreen="true" mozallowfullscreen="true" webkitallowfullscreen="true"></iframe>
