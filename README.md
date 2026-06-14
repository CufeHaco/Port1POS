# Port1POS

A modern JRuby-based Point of Sale system for liquor stores, designed as a drop-in replacement for LiquorPOS on Windows 11.

## Goals
- Full compatibility with existing LiquorPOS DBF database files (`LPOSData/*.dbf`) for seamless migration.
- Reuse existing barcode scanners, thermal printers, cash drawers.
- Print server compatibility layer (existing Ruby code).
- Windows SMB stack fixes integration.
- Sovereign, auditable system using Kestówv/Spinel/Rubian where applicable.
- Touch-friendly UI for registers.

## Tech Stack
- JRuby (primary)
- `dbf` gem for DBF compatibility
- JavaFX/Swing or web-based frontend for POS UI
- Warbler or similar for .exe packaging
- Ruby for print server & SMB layers

## Project Structure
```
Port1POS/
├── Gemfile
├── README.md
├── lib/
│   ├── compatibility/     # DBF, print, SMB layers
│   ├── pos/               # Core POS logic
│   ├── ui/                # UI components
│   └── hardware/          # Scanner, printer integrations
├── bin/
│   └── port1pos           # Entry point
├── config/
├── db/                    # Migration scripts, schemas
├── test/
└── docs/
```

## Quick Start
1. Clone the repo
2. `bundle install`
3. Run with JRuby

## Migration
Direct read/write to LiquorPOS DBF files.

## Contributing
See issues or contact @CufeHaco.