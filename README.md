# Port1POS

A modern JRuby-based Point of Sale system for liquor stores, designed as a drop-in replacement for LiquorPOS on Windows 11.

## Key Features
- Full compatibility with LiquorPOS DBF database files and logs
- Print server compatibility layer for reliable receipt printing
- Hardware reuse: existing barcode scanners and printers
- Sovereign/auditable design using Kestówv stack
- Linux/Windows cross-platform, with .exe packaging

## Architecture
- `lib/compatibility/`: DBF reader, print server, SMB fixes
- JRuby + Warbler for deployment

## Getting Started
1. `bundle install`
2. Configure data paths for LiquorPOS DBF files

Contributions welcome!