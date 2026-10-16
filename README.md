# Looking For Work

A WoW Forever addon for finding who in your guild can craft a recipe, whether they are online or offline.

## Features

- **Saves your professions**: open a profession window once and Looking For Work saves its *whole* recipe list (learned and unlearned recipes, with categories, reagents, tools and what each recipe makes) plus which recipes your character knows. Recipes you learn later are added automatically.
- **Guild sharing**: guild members who also use Looking For Work share their professions with each other, so you can see what offline members can craft too.
- **Window laid out like the WoW Forever profession window** (`/lfw`):
  - A **tab for every profession** down the right-hand edge (Alchemy, Blacksmithing, Enchanting, Engineering, Herbalism, Leatherworking, Mining, Skinning, Tailoring, Cooking, First Aid, Fishing), with the **Options** tab on top
  - **Left**: search box, **Filter** button and **every recipe** grouped under collapsible category bars, including the ones nobody in the guild has (shown in grey)
  - A dot in front of each recipe: **green** = an online guild member has it, **gold** = only offline members have it, none = nobody has it. The number on the right is how many members have it
  - **Right**: click a recipe to see its icon, description, what it creates, tools required, **reagents** (with how many you have in your bags) and the **crafters** list: each member's **First-name Last-name** in class colour, **Online / Offline** status (zone when online, how long ago when offline) and their skill
  - **To Craft** and **Profit** under the reagents, from **Auctionator** prices (see below)
  - The bar at the top shows how many of the profession's recipes are known somewhere in the guild
- **Options tab**:
  - **Update** asks your guild for their professions
  - **Ignore Queries** (unchecked by default): when checked you don't answer other members' Update requests and your professions are not shared automatically
  - **Your Characters**: every character you have logged in with, its professions and whether each one's recipes are saved yet
  - **Guild Members Sharing Data**: everyone you have data for, online first, with a Forget button to clear it
  - **Recipe Lists**: how many recipes are saved for each profession

## Installation

1. Copy the `LookingForWork` folder into:
   ```
   World of Warcraft\_forever_\Interface\AddOns\LookingForWork\
   ```
2. `/reload` or restart the game.

The Ace3 libraries it needs (LibStub, CallbackHandler, AceComm-3.0 with ChatThrottleLib, AceSerializer-3.0) are included in the `Libs` folder, so nothing else has to be installed.

## Getting started

1. On each of your characters, open every profession window once (default key **K**, then click the profession). This saves the full recipe list and what that character knows.
2. Open `/lfw`, go to the **Options** tab and press **Update**.
3. Click a profession tab, then a recipe, to see who can make it.

## How guild sharing works (and why it stays light)

- **Guild only.** All messages go over the GUILD addon channel. Nothing is sent to whispers, groups, raids or public channels, and data from anyone not on your guild roster is ignored.
- **Update** sends one small request listing which version of each member's data you already have. Only members whose data you are missing or have an older copy of reply, after a short random delay so replies don't all arrive at once. Each reply goes to the whole guild channel, so one reply updates every addon user at the same time.
- **Update can be pressed once a minute** (the button shows a countdown).
- **Recipe lists** (the full list of every recipe in a profession) are only sent when someone's list is smaller than yours. If several members could send the same list, the first one announces it and the others stand down, so it goes out once.
- **Missing recipe lists are requested automatically.** Shared data says how big the sender's recipe lists are. If a guild member's data arrives for a profession whose list you don't have (or yours is smaller, or is missing recipes they know), your addon asks that member for it. The same list is asked for at most once every 10 minutes, and if someone else already asked, you just receive their answer.
- **Automatic sharing**: when your own professions change (new recipe, skill-up, newly scanned profession), your data is shared once, a minute later, and at most once every 5 minutes. Turned off by Ignore Queries.
- Members only ever send **their own characters' data**, never other people's.
- Messages are queued through ChatThrottleLib (part of Ace3), which keeps the send rate under the game's limits. Nothing is sent during combat; it waits until combat ends.
- Your own alts in the same guild are shared too, so guild mates can see what your offline alts can craft.

**Offline members**: you see an offline member's recipes once you have received their data, which happens whenever you and they (or one of their alts) are online with the addon at the same time. It is saved, so it stays available after they log off.

## Every recipe, even ones nobody has

The game lists every recipe of a profession in its profession window, including ones you haven't learned. Looking For Work saves that full list whenever anyone opens the window, and shares it with the guild. So a profession tab shows every recipe as soon as **one** guild member with the addon has opened that profession.

Until then the tab shows the recipes known by members who have shared their data, plus a note on how to get the full list.

Click a profession link someone posts in chat: when it opens, Looking For Work also saves the recipe list from it, and if the person is a guild member, which recipes they know.

## Crafting cost and profit (Auctionator)

When [Auctionator](https://www.curseforge.com/wow/addons/auctionator) is installed, the recipe panel shows two lines under the reagents, like Auctionator does in the game's own profession window:

- **To Craft**: the total cost of the reagents. Each reagent uses the cheaper of its vendor price (if Auctionator has seen it at a vendor) and its latest auction house price.
- **Profit**: what the crafted item sells for on the auction house (times how many the recipe makes), minus the auction house's 5% cut, minus the To Craft cost. Shown in red when you would lose money.

Hover either line for a breakdown: each reagent's price (and whether it's a vendor or auction price), the sale price, the auction house cut, and how old the oldest price is.

- Recipes that don't make an item (most enchants) show **To Craft** only.
- Reagents Auctionator has no price for are listed as "without a price", and the profit is marked as an estimate.
- If Auctionator isn't installed, the panel says so. Auctionator needs at least one auction house scan for prices to appear; prices refresh whenever you close the auction house.

Prices come from the same places as AH Lookup: `Auctionator.API.v1.GetAuctionPriceByItemID` (and `GetVendorPriceByItemID`), falling back to Auctionator's saved price table.

## Names

WoW Forever names are "First-name Last-name". On WoW Forever `UnitName()` returns the first name and surname as two separate values, so Looking For Work joins them (or uses `GetUnitName()`) to always save the complete name. Members are matched by their character GUID, so names with spaces or hyphenated last names are never a problem. Names and classes are kept in step with the guild roster.

## Commands

| Command | Effect |
|---|---|
| `/lfw` or `/lookingforwork` | Open / close the window |
| `/lfw <profession>` | Open a profession tab, e.g. `/lfw tailoring` |
| `/lfw find <text>` | Search every profession (names, tooltip text, reagents, players); opens the one with the most matches |
| `/lfw update` | Ask your guild for their professions (same as the Update button) |
| `/lfw ignore` | Turn Ignore Queries on/off |
| `/lfw options` | Open the Options tab |
| `/lfw debug` | Show version, saved counts, and turn debug messages on/off |
| `/lfw help` | Show help |

Looking For Work also appears in the game's **Options → AddOns** list and in the addon compartment (the button by the minimap).

## Tips

- **Search** matches recipe names, **tooltip text**, what a recipe creates, reagent names and crafter names:
  - Tooltip text covers the recipe's own tooltip and the tooltip of the item it makes, so `defense` finds *Enchant Bracer - Minor Deflect* (its tooltip says it increases Defense) and `intellect` finds food whose tooltip says it gives Intellect.
  - Hover a recipe while searching to see why it matched, e.g. *Found by search — Tooltip: Permanently enchant bracers to increase Defense by 1.*
  - Typing a guild mate's name shows everything they can make.
- **Filter**: show or hide recipes nobody has, show only recipes with an online crafter, expand or collapse all categories.
- Click a selected recipe again to go back to the profession overview, which lists every guild member with that profession, their skill and how many recipes they have shared.
- Click a crafter to whisper them. Shift-click a recipe, its icon or a reagent to link it in chat.
- Members who have a profession but haven't shared their recipes yet are listed under a recipe as "has Enchanting, recipes unknown".

## Saved data

Everything is stored account-wide in the `LookingForWorkDB` SavedVariable:

```lua
LookingForWorkDB = {
    settings = { ignoreQueries = false, showUnowned = true, onlineOnly = false },
    catalog  = {   -- every recipe of each profession
        enchanting = { cats = { ["Camping"] = 1, ... },
                       recipes = { [1230643] = { n = "Enchanted Lute", c = "Camping",
                                                 r = { {4470, 1}, ... }, o = <item made>, q = "tools" } } },
    },
    players  = {   -- by character GUID
        ["Player-1234-0ABCDEF1"] = { name = "John Smith", class = "MAGE", guild = "Realm|Guild", rev = 7,
                                     profs = { enchanting = { lvl = 24, max = 75, known = { [1230643] = true } } } },
    },
    sync = { lastQuery = ..., lastSent = { ... } },
    collapsed, icons, positions,
}
```

## Changes

**1.3.0**
- Fix: a profession could show every recipe under "Other" when a guild member's data arrived through automatic sharing rather than an Update, because the recipe list wasn't sent with it. Missing recipe lists are now requested from that member automatically.
- Fix: recipes received from guild members could show a generic placeholder icon. Recipe icons are now shared, and the icon of the item a recipe makes is used before the recipe spell's icon.
- The header bar says when a profession's recipe list hasn't been received yet.

**1.2.0**
- **To Craft** and **Profit** lines in the recipe panel, using Auctionator's prices, with a hover breakdown per reagent.

**1.1.0**
- Search also looks through recipe tooltips and the tooltip of the item each recipe makes, so you can search for a stat or effect (`defense`, `intellect`, `fire resistance`) that isn't in the recipe's name. `/lfw find` does too.
- Hovering a recipe during a search shows which text matched.
- Tooltip text is read in the background when you open a profession tab, so searching stays quick.

**1.0.0**
- First release.
