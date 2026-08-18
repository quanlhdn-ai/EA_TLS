# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

MetaTrader 5 (MT5) algorithmic trading system written in MQL5. The repo is organised as **one folder per bot**, each self-contained with its own source, saved `.set` preset, journal, and backup zips.

| Folder | Main source | Notes |
|---|---|---|
| `BOT_CRT/` | `CRT_MultiTF_EA.mq5` | CRT (Candle Range Theory). Two boundary sources (adjacent HTF candle + Last Major Swing) running in parallel, separated by magic number. |
| `BOT_TLS/` | `TLS_SMC_CSV_Bot.mq5`, `TLS_SMC_Indicator.mq5` | SMC bot. Reference implementation for order limits, Shield, Telegram — other bots port mechanisms from here. |
| `BOT_OB_Radar/` | `BOT_OB_Radar.mq5` | Order Block radar. Also carries its own `OB_CSMC_Engine.mqh`. |
| `BOT_ChartSnapshot/` | `Combo_Structure_ChartSnapshot_Bot.mq5` | Chart snapshot bot, uses `Telegram_ChartBot.mqh`. |
| `Docs/` | — | `CRT_Ebook`, strategy spreadsheets. Reference only. |
| `Indicator_TradingView/` | `ChibaoTradingView.txt` | Pine Script v6 SMC indicator. Reference only; never compiled. |
| `OlderVersion/` | — | Archived sources. Do not edit; do not treat as current. |

Each bot folder has a `Nhatky_<BOT>.txt` journal in Vietnamese. **Read the relevant journal before making changes** — it records past decisions, deliberate non-fixes, and the reasoning behind rules that look wrong out of context.

## Shared includes — must never diverge

`CSMC_Engine.mqh` and `Telegram_Radar.mqh` are **byte-identical copies** kept in `BOT_CRT/`, `BOT_TLS/`, and `BOT_OB_Radar/`.

Editing one means mirroring it to every other copy in the same change. Verify afterwards:

```bash
md5sum BOT_*/CSMC_Engine.mqh BOT_*/Telegram_Radar.mqh
```

All hashes for a given filename must match. A silent divergence here breaks bots that were not being worked on and is very hard to trace later.

Both are included with angle brackets (`#include <CSMC_Engine.mqh>`), so the compiler resolves them from `<MT5 data folder>/MQL5/Include/`, **not** from the bot folder.

## Build

MetaEditor ships a working command-line compiler — use it, don't ask the user to press F7.

```powershell
$DF = 'C:\Users\Admin\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075'

# Source of truth is this repo; MT5 folders are deploy targets.
Copy-Item 'BOT_CRT\CRT_MultiTF_EA.mq5' "$DF\MQL5\Experts\" -Force
Copy-Item 'BOT_CRT\CSMC_Engine.mqh'    "$DF\MQL5\Include\" -Force
Copy-Item 'BOT_CRT\Telegram_Radar.mqh' "$DF\MQL5\Include\" -Force

& 'C:\Program Files\MetaTrader 5\MetaEditor64.exe' `
    /compile:"$DF\MQL5\Experts\CRT_MultiTF_EA.mq5" /inc:"$DF\MQL5" /log:"$env:TEMP\build.log"
Get-Content "$env:TEMP\build.log" -Encoding Unicode | Select-String ': error |: warning |^Result:'
```

Gotchas:

- The log is **UTF-16** — read it with `-Encoding Unicode` or it comes out as mojibake.
- MetaEditor returns a **non-zero exit code even when only warnings exist**. Judge success by the `Result: N errors` line, never by the exit code.
- Three warnings are pre-existing and harmless across these bots: `POSITION_COMMISSION is deprecated` (×2) and a `ushort`→`uchar` conversion in `Telegram_Radar.mqh`.
- Compiling writes `.ex5` next to the `.mq5` inside the MT5 folder. The Strategy Tester picks it up on the next run; no manual copy needed.

Backtesting still needs the MT5 GUI (Strategy Tester). `WebRequest` is blocked there, so `TELEGRAM POST ERROR: Code -1 | Error: 4014` is normal in backtests and is not a bug.

## Working conventions

- **`.set` files are UTF-16LE with BOM.** Format is `Name=value||start||step||stop||optimize`. MT5 matches by name, not position, but keep code order and `.set` order in sync anyway — it makes diffing possible. After adding or removing an `input`, update the `.set` in the same change and verify the counts match.
- **Cosmetic settings are `const`, not `input`.** Colors, widths, line styles, label toggles, extend-bars. The user wants the Inputs screen to carry operational parameters only. Input descriptions are written in plain Vietnamese, short enough to display fully.
- **Enum identifiers cannot contain Vietnamese diacritics or spaces**; the comment beside them can.
- **A function taking a struct parameter must be declared after that struct** — MQL5 has no forward declaration for this.
- **Gold pip convention on this broker:** 1 pip = $0.1 = 100 × point. Quotes show 3 decimals but pips behave like a 2-decimal broker.
- **Every order/position loop filters on magic number** so the bot ignores manually placed trades and the other source's trades.
- **Log lines are prefixed** `[BOT][module]` for terminal filtering.
- **Journal and backup zip are opt-in.** Write them only when the user asks — never as an automatic follow-up to a code change.

## Secrets

Telegram bot tokens and channel IDs are currently **hardcoded** in some bot sources and `.set` files at the user's explicit request. This repo is a git repository — pushing it to a public remote would expose them. Flag this before any operation that publishes the repo; do not silently rewrite the credentials out.
