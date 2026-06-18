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

**Important: Tk GUI Setup**  
Port1POS includes a Tk-based register GUI (`lib/gui/tk_main.rb`).  
Modern Ruby/JRuby Tk support requires Cufe's updated patch:

```bash
git clone https://github.com/CufeHaco/rubytk_patchV2
cd rubytk_patchV2
ruby rubytk_install.rb
```

This script handles dependencies, symlinks, and verification on Ubuntu, macOS, and Windows.  
Run it once before using the GUI.

### Quick Start
1. `bundle install`
2. (If using GUI) Run the Tk patch above
3. `ruby lib/gui/tk_main.rb`   # standalone demo
4. Configure data paths for LiquorPOS DBF files (when DBF layer is complete)

Contributions welcome!