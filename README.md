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

### Prerequisites
- Ruby 3+ or JRuby 10.1+
- Tcl/Tk 8.6 (for the GUI)

**Important: Tk GUI Setup (Integrated)**  
Port1POS includes a full Tk register GUI. The Tk installer is now built-in:

```bash
ruby setup/install_tk.rb
```

This is Cufe's rubytk_patchV2 logic integrated directly into Port1POS (self-contained, updated for Linux/macOS/Windows + JRuby notes). It handles everything needed for `require 'tk'` to work.

Run it once before `ruby lib/gui/tk_main.rb`.

### Quick Start
1. `bundle install`
2. (If using GUI) Run `ruby setup/install_tk.rb`
3. `ruby lib/gui/tk_main.rb`   # standalone demo
4. Configure data paths for LiquorPOS DBF files (when DBF layer is complete)

Contributions welcome!