# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a MetaTrader 5 (MT5) algorithmic trading system written in MQL5. The repository contains:

- [TLS_EA.mq5](TLS_EA.mq5) — Expert Advisor (~3072 lines). All trade logic, risk management, session gating, and Telegram notifications.
- [TLS_EMA.mq5](TLS_EMA.mq5) — Custom EMA indicator. Draws EMA10/EMA39 lines, cross dots, and the HighLine/LowLine channel levels that the EA reads as breakout thresholds.
- [TLS_HA.mq5](TLS_HA.mq5) — Custom Heikin-Ashi indicator. Provides candle color (bull/bear), OHLC values used for SL placement and trend bias.
- [ChibaoMT5.txt](ChibaoMT5.txt) — TradingView Pine Script v6 SMC indicator (BOS/ChoCh, Order Blocks, Supply/Demand zones). Reference only; not compiled or used by the EA.

## Build & Deployment

MQL5 has no command-line compiler. Compilation is done inside **MetaEditor** (ships with MetaTrader 5):

1. Open the `.mq5` file in MetaEditor.
2. Press `F7` to compile. Errors and warnings appear in the Errors tab.
3. The compiled `.ex5` file is written to the same directory.

**Deployment order** (both indicators must exist before attaching the EA):
1. Copy `TLS_HA.ex5` and `TLS_EMA.ex5` → `<MT5 data folder>/MQL5/Indicators/`
2. Copy `TLS_EA.ex5` → `<MT5 data folder>/MQL5/Experts/`

The EA locates its indicators by name via the `HAIndicatorName` and `EMAIndicatorName` input parameters; these must match the installed `.ex5` filenames exactly.

## Architecture

### Signal Flow

```
EMA cross detected (TLS_EMA buffers) → set waitingBUY or waitingSELL
  → each new bar: CheckBuyBreakoutOnClosedBar / CheckSellBreakoutOnClosedBar
      → pass all filters → ExecuteEntry() → market or limit order placed
```

### Regime System

Every EMA crossover begins a new **regime** (`currentRegimeEpoch` = timestamp of the cross bar). Each HighLine/LowLine price level is allowed to fire **once per regime**. State is tracked in:
- `usedLines[]` in memory, persisted to `TLS_LineUsed.dat` (binary)
- Key = `(regimeEpoch, LineKey(price), isBuy)`

A cross resets the epoch; the same price level in a new regime is a fresh, unused setup.

### Entry Filter Chain (runs on each new bar)

`CheckBuyBreakoutOnClosedBar()` / `CheckSellBreakoutOnClosedBar()` require all of:
1. `waitingBUY` / `waitingSELL` arm is set
2. Price zone filter activated (if `EnablePriceZoneFilter = true`)
3. HA candle at bar[1] is correct color (bull for buy, bear for sell)
4. HA close is above HighLine / below LowLine at bar[1]
5. Regular candle at bar[1] is in the same direction (close vs open)
6. Line not already used in this regime
7. Channel width ≥ `RangeChannelEMA` pips

Entry type decision in `ExecuteEntry()`:
- **Market order** when SL distance ≤ `SLMaxPips`
- **Limit order** at `sl ± SLMaxPips` when SL distance exceeds the cap

### Price Zone Filter

Up to 10 buy zones and 10 sell zones can be configured as inputs. The EA gates entries until price touches a matching zone (within `ZoneActivationPips`). Zones are single-use and persisted to `TLS_ZoneUsed.dat`. An opposite cross deactivates the current-side zone.

### Risk Sizing

`CalcLotsByRiskUSD()`: `lots = RiskUSDPerTrade / (sl_pips × pipValuePer1Lot)`

SL is sourced from `FindSLFromNearestOppositeHAPair()`: scans back up to `SL_LookbackBars` for two consecutive opposite-color HA candles, then sets SL at their low/high ± `BufferPips`.

TP on M1: `entry ± RiskReward × risk_distance`. On HTF (non-M1 timeframes): `entry ± HTF_TP_Prices`.

### Session Gating (`TradeWindowMode`)

- **FULLDAY** — trades during broker session hours; blocks entries within `NoNewTradesBeforeEndH` hours of session end; force-closes all positions at session end.
- **SESSIONS** — trades only during configured VN-timezone windows (Asia/EU/NY). Breakouts that form outside the allowed window are marked as used (anti-FOMO) rather than held for later.

DD gate: Blocks new trades when realized session loss ≥ `DailyDD_Percent%` of session opening balance, or when the next trade would push over the limit.

Profit gate: Blocks new trades once `DailyProfitTargetUSD` is reached for the session.

### Position Management (`ManageBreakEvenAndCrossRules`)

- **M1**: Optional break-even at ~1R (`IsAllowBE`). On opposite cross, modify SL to entry if the position is profitable, or set TP to entry if not.
- **HTF**: Close position on opposite cross if currently profitable.

### Indicator Buffer Layout

| Handle | Buffer 0 | Buffer 1 | Buffer 2 | Buffer 3 | Buffer 4 |
|--------|----------|----------|----------|----------|----------|
| `haHandle` (TLS_HA) | HA Open | HA High | HA Low | HA Close | Color (0=bull, 1=bear) |
| `emaHandle` (TLS_EMA) | Short MA | Long MA | Cross Dot | HighLine | LowLine |

All buffers are read with `CopyBuffer()` using series indexing (index 0 = current bar, 1 = last closed bar).

### Telegram Module

`OnTradeTransaction()` handles order creation, fills, and TP/SL exits. Messages are deduplicated via MT5 `GlobalVariable` flags keyed by `_Symbol + _Period + kind + orderID`. Configure `TG_BotToken` and `TG_ChatID` inputs; set `EnableTelegram = false` to disable entirely.

## Key Conventions

- `PipSize()` normalizes pip units across Forex (5-digit), gold (3-digit), and CFD instruments.
- All order/position iteration checks `MagicNumber` so the EA ignores manually placed trades.
- Core logic runs once per bar inside `IsNewBar()`, not on every tick.
- Log lines follow `[SYMBOL][MODULE][SIDE]` prefix format for easy terminal filtering.
- `IndicatorsReady()` auto-recreates indicator handles if they stall for > 30 retries.
