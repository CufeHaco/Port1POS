# Port1POS Build Book

## Project Overview
Similar but better JRuby replacement for LiquorPOS on Windows 11.

## Performance Tuning (JRuby 10.1)

JRuby 10.1 defaults: invokedynamic, reduced object sizes, better GC.

Recommended flags:
- -J-Xmx4g -J-XX:+UseG1GC
- -Xjit.threshold=0 for POS hot paths.

## Edge Cases Report for Charles

- Concurrent multi-register DBF access and locking.
- Print stream edge cases (partial data, premature cuts).
- Age verification failures, offline mode sync.
- Case/pack/bottle breakdown math under high volume.
- GA compliance hours boundary cases.

More details to be added as we progress.