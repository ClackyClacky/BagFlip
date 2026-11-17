# BagFlip

A World of Warcraft addon for **WoW Forever** that answers one question for every item in your bags: *sell it to the vendor, or put it on the auction house?* Then it sells in one click, or gets the item ready for you to post.

![Interface 16001](https://img.shields.io/badge/WoW%20Forever-16001-blue)

## What it does

Type `/bf` to open a list of everything in your bags, reagent bag and bank. For each item it shows:

| Column | Meaning |
|---|---|
| Vendor | What a vendor pays for the whole stack (from the game) |
| Auction (after cut) | What you'd get on the auction house after the 5% cut and the 1s deposit |
| AH profit | How much more the auction house pays than the vendor (red when the vendor pays more) |
| Do this | **Auction** if the auction house pays more, otherwise **Vendor** (or **Keep / bin**), plus notes like *scan 5d old* or *no auction data* |

The verdict is pure profit: whichever pays more wins, however small the difference. Use the *AH profit* column to decide whether a small gain is worth listing.

Bank items get their own section below your bags, under a **Bank** heading. At the top, BagFlip totals what your bags would fetch if you vendored everything versus followed its advice; the Bank heading shows the same totals for the bank.

## Prices

- **Vendor prices** come from the game.
- **Auction prices** come from your own [Auctionator](https://www.curseforge.com/wow/addons/auctionator) scans: the cheapest listing in your latest scan. BagFlip matches that price rather than undercutting it. Do a **Full Scan** on Auctionator's tab at the auction house; there's no need to `/reload` afterwards. Scans 2 days old or more are still used, with a note saying how old they are.

Without Auctionator, nothing has an auction price, so everything says Vendor.

## One-click selling, and items ready to post

Hover a row to see what a click will do.

**At a vendor**, clicking a row sells every stack of that item from your bags. Made a mistake? Use the vendor's Buyback tab.

**At the auction house**, clicking a row puts that item in Auctionator's **Selling** tab. Check the price and quantity there and click **Post** yourself. BagFlip never posts anything on its own. Auctionator sets the price from its own selling settings; set its undercut to 0 if you want to match the cheapest listing. Without Auctionator, it uses the game's own Sell tab.

To stop one stray click going the wrong way:

- Rows marked **Auction** need **Shift-click** to sell to a vendor.
- With neither window open, clicking does nothing, so it can never use or equip an item by mistake.
- Bank items and soulbound items can't be put up for auction.

## Bank

The game only lets addons read your bank while you're at it. BagFlip saves the bank's contents each time you visit and shows them in the Bank section the rest of the time. This is saved per character. Take bank items out to sell or post them.

## Options

| Option | How |
|---|---|
| Include bank items | Checkbox in the window, or `/bf bank` |
| Open at vendors | Checkbox in the window, or `/bf vendor` |
| Open at auction house | Checkbox in the window, or `/bf ah` |

When BagFlip opened on its own at a vendor or the auction house, it closes again when you leave.

## Install

1. Install [Auctionator](https://www.curseforge.com/wow/addons/auctionator) if you don't have it.
2. Download this repository (**Code → Download ZIP**) and unzip it.
3. Copy the `BagFlip` folder into `World of Warcraft\_forever_\Interface\AddOns\`.
4. Restart the game or type `/reload`, then do a Full Scan at the auction house.

## Tuning

The numbers at the top of `BagFlip.lua`:

| Setting | Default | Meaning |
|---|---|---|
| `AH_CUT` | `0.05` | Faction auction house cut |
| `DEPOSIT` | `100` | Deposit per listing in copper (1s). Change to `1` if the 1c deposit goes live |

## Privacy

BagFlip sends nothing anywhere. It saves your settings and each character's bank contents (keyed by character name and realm) in WoW's normal `SavedVariables` file on your own PC.
