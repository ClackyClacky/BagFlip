# BagFlip

A World of Warcraft addon for **WoW Forever (EU PvP)** that answers one question for every item in your bags: *sell it to the vendor, or list it on the auction house?*

![Interface 16001](https://img.shields.io/badge/WoW%20Forever-16001-blue)

## What it does

Type `/bf` to open a list of everything in your bags, reagent bag and bank. For each item it shows:

| Column | Meaning |
|---|---|
| Vendor | What a vendor pays for the whole stack (from the game) |
| Auction (after cut) | What you'd get on your faction's auction house after the 5% cut and the deposit |
| Sales/day | How many sell per day across EU Forever (TSM data), a rough guide to demand |
| Do this | **Auction**, **Vendor** or **Keep / bin**, plus warnings like *sells slowly* or *none listed now* |

At the top it totals what you'd get for vendoring everything versus following its advice.

### Selling

- **Click a row while talking to a vendor** to sell every stack of that item.
- Rows marked **Auction** need **Shift-click**, so you don't sell something the auction house would pay more for.
- Clicking does nothing if no vendor is open, so it can never use or equip an item by mistake.
- Bank items and things vendors won't buy can't be sold from the list.
- Made a mistake? Use the vendor's Buyback tab.

### Bank

The game only lets addons read your bank while you're at it. BagFlip saves the bank's contents each time you visit and shows them (marked *(bank)*) the rest of the time. This is saved per character.

### Options

| Option | How |
|---|---|
| Include bank items | Checkbox in the window, or `/bf bank` |
| Open at vendors | Checkbox in the window, or `/bf vendor`. If BagFlip opened on its own, it closes when you leave the vendor |

## Install

1. Download this repository (**Code → Download ZIP**) and unzip it.
2. Copy the `BagFlip` folder into `World of Warcraft\_forever_\Interface\AddOns\`.
3. Restart the game or type `/reload`.

[Auctionator](https://www.curseforge.com/wow/addons/auctionator) is optional. If installed, BagFlip uses your own recent scans (up to 2 days old) ahead of the bundled snapshot.

## Where the prices come from

- **Vendor prices:** the game itself.
- **Auction prices:** `Prices.lua`, a snapshot of the EU PvP Horde and Alliance auction houses taken on **10 November 2026**. It doesn't update itself, so it gets less accurate over time. A recent Auctionator scan is more accurate.
- **Sales per day:** TradeSkillMaster's public EU Forever region data.

## Tuning

The numbers at the top of `BagFlip.lua` decide the verdicts:

| Setting | Default | Meaning |
|---|---|---|
| `AH_CUT` | `0.05` | Faction auction house cut |
| `DEPOSIT` | `100` | Deposit per listing in copper (1s). Change to `1` if the 1c deposit goes live |
| `MIN_GAIN` | `100` | The auction must beat the vendor by at least this much copper per stack... |
| `MIN_RATIO` | `1.10` | ...and pay at least this many times the vendor price |
| `SLOW_SALES` | `0.5` | Below this many sales per day, the item is flagged *sells slowly* |

## Privacy

BagFlip sends nothing anywhere. It saves your settings and each character's bank contents (keyed by character name and realm) in WoW's normal `SavedVariables` file on your own PC.
