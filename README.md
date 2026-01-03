# rsg-election

**rsg-election** is a government election and voting framework for **RedM** servers using **RSGCore**, designed to support immersive, region-based political roleplay.  
It enables servers to run structured elections for public offices such as **Governor**, **Mayor**, or other configurable positions, fully integrated with regional systems, residency, and government authority mechanics.

---

## Purpose

This resource provides a **server-authoritative election system** that allows players to:

- Run for public office  
- Register as candidates  
- Vote during scheduled election periods  
- Assume government roles based on election results  

It is intended to work as part of a **larger government framework**, not as a standalone minigame.

---

## Key Features

### Configurable Elections
- Multiple offices supported  
- Custom election schedules  
- Controlled registration and voting phases  

### Candidate Management
- Candidate registration with validation  
- Optional NPC-based election clerks  
- Server-side candidate lifecycle handling  

### Secure Voting System
- One vote per eligible player  
- Server-validated vote casting  
- Protection against duplicate or invalid votes  

### Region-Aware Integration
- Elections tied to specific regions  
- Designed to integrate with `rsg-governor`  
- Compatible with residency and regional authority logic  

### Government Role Assignment
- Automatic assignment of elected roles  
- Hooks for salary, treasury, and permissions  
- Designed for use with payroll and taxation systems  

---

## Design Philosophy

- **Server-authoritative** (no client-trusted results)  
- **Framework-first** (logic-focused, UI-agnostic)  
- **Modular and extensible**  
- Built for **serious roleplay servers**, not arcade voting  

---

## Intended Integrations

- `rsg-core` – player, job, and money framework  
- `rsg-governor` – region control and authority  
- `rsg-residency` – voter eligibility and residency checks  
- `rsg-economy` – salaries, taxes, and treasury routing  

Each integration is optional but **strongly recommended** for full functionality.

---

## Use Cases

- Governor elections per region  
- Mayoral or municipal elections  
- Term-based leadership roleplay  
- Government legitimacy systems  
- Political campaigns and debates  

---

## Notes

- No UI is bundled by default (framework-level resource)  
- Designed to be extended with:
  - Campaign mechanics  
  - Debates  
  - Term limits  
  - Impeachment systems  
