# Port1POS Build Book - Living Job Site Transcript

## Project Overview
Similar but better JRuby replacement for LiquorPOS on Windows 11. Full DBF compatibility, hardware reuse (scanners, printers), dynamic boot style.

## Coding Philosophy
Arrays everywhere → string/index pattern matching → StringIO/bytearrays → Build → Match → Verify → Execute.
Dynamic discovery, no rigid static directory trees.

## Tech Stack
- JRuby 10.1
- JEP-380 IPC + Windows named pipe fallback
- Thread-local builtin tracking + byte/BOP tracker
- Tk for dialogs (threaded)
- GPL-3.0 license

## Server Side
- DBF host, print proxy, inventory receiving with case/pack/bottle breakdowns
- Reporting, GA compliance

## Register Side
- Transaction loop: scan → unit resolution → age prompt → tender → print

## Micro IPC & Print Server
See micro_ipc.rb and print_server sketches for byte tracking.

## Performance Tuning
JRuby 10.1 defaults, G1GC, etc.

## Georgia Compliance
Age verification (appears <30), hours, keg logging, local auditable logs.

## Edge Cases
Multi-register locking, print failures, offline sync, etc.

(Full details from conversation history)