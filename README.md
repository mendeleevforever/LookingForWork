# Looking For Work

Find out who in your guild can craft a recipe, online or offline.

Looking For Work keeps a list of every recipe in every profession, including the ones nobody in your guild knows yet, and shows who can make each one. Guild members who use the addon share their professions with each other automatically, and crafters who don't use it can be added from their profession links.

## Features

- **Every recipe in one place.** A tab for each of the twelve professions, with every recipe grouped by category, just like the game's own profession window.
- **Who can craft it.** Click a recipe to see its reagents and everyone who knows it, with their online status, zone and skill.
- **Works for offline members.** What your guild mates share is saved, so you can still see what they can make after they log off.
- **Search by name or by effect.** Search `intellect`, `defense` or `fire resistance` to find recipes by what they do, or type a guild mate's name to see everything they can make.
- **Crafters outside your guild.** People who link their profession in Trade or other chat channels are remembered too.
- **Crafting cost and profit.** With Auctionator installed, see what a recipe costs to make and what you'd earn selling it.
- **What a recipe costs to buy.** See a recipe's auction house price and vendor price (including other currencies like badges and marks), and the skill needed to learn it.
- **Filter and sort.** Show recipes you know or don't know, filter by the rarity of what they make, and sort by skill to learn, recipe price, cost to craft, rarity, disenchant profit or vendor profit.
- **Minimap button** and a `/lfw` command to open it anywhere.

## Installation

Install it with the CurseForge app, or copy the `LookingForWork` folder into:

```
World of Warcraft\_forever_\Interface\AddOns\
```

Then restart the game. If Looking For Work doesn't appear in the AddOns list, close the game completely and start it again. Everything it needs is included.

**Optional:** install [Auctionator](https://www.curseforge.com/wow/addons/auctionator) to see crafting costs and profit.

## Getting started

1. **Open each of your professions once** on every character (press **K**, then click the profession). This saves the profession's full recipe list and the recipes that character knows. New recipes you learn later are added automatically.
2. **Type `/lfw`** (or click the minimap button) to open Looking For Work.
3. **Press Update** on the Options tab (the gear at the top of the tabs) to get your guild mates' professions.
4. **Click a profession tab, then a recipe,** to see who can make it.

## The window

**Tabs (right edge):** the Options tab at the top, then one tab per profession. Faded tabs have no data yet.

**Recipe list (left):**
- Every recipe, grouped under category bars. Click a bar to fold or unfold it.
- A **green dot** means someone online can make it, a **gold dot** means only offline members can, a **blue dot** means only crafters outside your guild can. No dot means nobody you know has it (shown in grey).
- The number on the right is how many guild members can make it; a blue **+3** counts crafters outside your guild.
- The bar at the top shows how many of the profession's recipes someone in your guild knows.

**Recipe details (right):**
- What the recipe makes, any tools it needs, and its reagents (with how many you're carrying).
- **Recipe:** the item that teaches it (for example *Pattern: Linen Cloak*), with its auction house price and vendor price, including other currencies, and the vendor's name and zone. For recipes not sold as an item, where it's learned (for example "Trainer").
- **Skill to learn**, when it's known.
- **To Craft** and **Profit**, if Auctionator is installed.
- **Crafters:** guild members who can make it, online first, then members who have the profession but haven't shared their recipes, then crafters outside your guild.
- **List All Enchanters** (List All Tailors, List All Chefs...) at the top right takes you back to everyone with that profession.

**In any crafter list:**
- **Click** a crafter to put a whisper link for them in your chat window; click the name there to whisper them.
- **Right-click** to open their profession, if they've linked it.
- **Hover** for their professions, skill, and where the information came from.

**Shift-click** a recipe, its icon or a reagent to link it in chat.

## Searching and filtering

The search box finds recipes by:
- recipe name and the name of the item it makes
- tooltip text, so `stamina`, `spirit` or `defense` finds recipes by their effect
- reagent names
- crafter names

Hover a recipe while searching to see why it matched. Categories open up when you search so nothing is hidden, and you can still fold them.

To search every profession at once, type `/lfw find <text>`.

**Filter** lets you:
- show or hide recipes you know and recipes you don't know (on the character you're playing)
- hide recipes nobody has
- show only recipes with a crafter who's online now
- include or hide crafters outside your guild
- show or hide each rarity of the item a recipe makes: Common, Uncommon, Rare, Epic, Legendary, Poor, or recipes that make no item (most enchants)
- **sort** by name, skill to learn, recipe price, cost to craft, rarity, **disenchant profit** or **vendor profit**. The value it's sorted by is shown on each row, and recipes without a value are listed last. The two profit sorts put the most profit at the top and losses at the bottom
- turn **Group by category** off to sort the whole profession as one list
- open or fold every category

If the list is empty, it tells you which filter or search is hiding the recipes.

## Guild sharing

Guild members who use Looking For Work share their professions with each other over the guild's addon channel. Nothing is ever sent outside your guild.

- **Update** (Options tab, right-click on the minimap button, or `/lfw update`) asks your guild for anything you're missing. You can use it once a minute. Everyone online who uses the addon is updated at the same time, so it rarely needs pressing.
- When your own professions change, they're shared automatically a minute later.
- You receive a guild mate's data whenever you're both online with the addon at the same time. It's saved, so it stays available after they log off.
- Your alts in the same guild are shared too, so guild mates can see what your offline alts can make.
- **Ignore Queries** on the Options tab stops you answering other members and stops your data being shared automatically. You still receive what others share.

## Guild members without the addon

Looking For Work reads the game's guild profession list after you log in, so guild members who don't use the addon still appear under their professions (for example "has Enchanting, recipes unknown").

To see which recipes they know, ask them to link their profession in guild chat and click the link. Their recipes are saved from then on.

Cooking, First Aid and Fishing aren't in the game's guild profession list, so for those only the addon and profession links can tell you who has them.

## Crafters outside your guild

- When someone links their profession in Trade, General, whispers or other chat, Looking For Work remembers who they are and keeps the link.
- Open the link (click it in chat, or right-click them in a crafter list) to save which recipes they know. Their guild is looked up at the same time if they're online.
- You only see crafters on the same **ruleset** (PvE, PvP, RP or Hardcore) and **faction** as the character you're playing, since nobody else can trade or craft with you.
- Crafters you find outside the guild are shared with guild mates who use Looking For Work, labelled with who found them.
- **Forget** next to *Outside your guild* on the Options tab, or `/lfw forget outside`, clears them.

## Crafting cost and profit

With Auctionator installed, each recipe shows:

- **To Craft:** what the reagents cost, using the cheaper of the vendor price or the latest auction house price for each.
- **Profit:** what the item sells for on the auction house, minus the auction house's 5% cut and the cost of the reagents. It's shown in red if you'd lose money.

- **Disenchant profit:** the average value of the materials you'd get from disenchanting what the recipe makes, at auction house prices after the 5% cut, minus the cost of crafting it. Items that can't be disenchanted show N/A and are listed after the ones that can. "(estimate)" means some material had no price, or the yields for that item level are estimated.
- **Vendor profit:** what a vendor pays for what the recipe makes, minus the cost of crafting it.

Hover any of these lines for a breakdown, including the chance and value of each disenchanting result. Recipes that don't make an item (most enchants) show **To Craft** only. Prices appear after Auctionator has scanned the auction house and refresh each time you close it.

## Recipe prices and skill

Looking For Work learns which item teaches each recipe as you play:
- from Auctionator's auction house scans
- when you open a vendor that sells recipes (this also saves the exact cost, including currencies like badges or marks)
- when you see a recipe item's tooltip, in your bags, the auction house or a link

**Recipe price** uses the auction house price first, then the vendor price. **Skill to learn** comes from the recipe item ("Requires Tailoring (75)"). Recipes that are only taught by trainers have no recipe item, so they show where they're learned instead and are listed last when sorting by skill or price.

## Options tab

- **Update** and how many characters' data arrived.
- **Guild directory:** how many guild members' professions were read from the game.
- **Ignore Queries.**
- **Your Characters:** each of your characters, their professions, and whether each profession's recipes are saved yet.
- **Guild Members Sharing Data:** everyone whose data you have, online first. **Forget** clears it; press Update to fetch it again.
- **Recipe Lists:** how many recipes are saved for each profession, and how many crafters outside your guild you know.

## Minimap button

- **Left-click:** open or close Looking For Work.
- **Right-click:** ask your guild for updates.
- **Drag:** move it around the minimap.

`/lfw minimap` hides or shows it. Looking For Work is also in the addon compartment next to the minimap, and in the game's **Options → AddOns** list.

## Commands

| Command | What it does |
|---|---|
| `/lfw` or `/lookingforwork` | Open or close the window |
| `/lfw tailoring` | Open a profession tab (any profession name works) |
| `/lfw find <text>` | Search every profession |
| `/lfw update` | Ask your guild for their professions |
| `/lfw ignore` | Turn Ignore Queries on or off |
| `/lfw minimap` | Show or hide the minimap button |
| `/lfw forget outside` | Forget crafters from outside your guild |
| `/lfw options` | Open the Options tab |
| `/lfw help` | List the commands |

## Questions

**A profession tab only shows a few recipes, all under "Other".**
Nobody has opened that profession's window with the addon yet, so only recipes people know are listed. As soon as anyone in your guild with the addon opens that profession (or you open someone's profession link), the full list appears.

**A guild mate is listed with "recipes unknown".**
They have the profession but don't use the addon. Ask them to link their profession in guild chat and click the link.

**I don't see someone I saw in Trade chat.**
They may play on a different ruleset or faction than your current character, or they linked a profession that isn't one of the twelve. Crafters outside your guild only appear once they've linked their profession.

**A recipe has no price or skill to learn.**
Looking For Work hasn't seen the item that teaches it yet. Scan the auction house with Auctionator, visit a vendor that sells it, or hover the recipe item. Recipes taught only by trainers don't have one.

**Update says to wait.**
Update can be used once a minute.

**Does it share anything outside my guild?**
No. Everything is shared over your guild's addon channel only.

## Changes

**1.7.0**
- Updated for WoW Forever's current addon rules. Your saved data carries over.
- Clicking a crafter now puts a whisper link in your chat window (addons can no longer open the chat box for you).

**1.6.2**
- Works with WoW Forever's change that hides realm names from addons: guilds are now told apart by ruleset and guild name, and your saved guild data carries over automatically.

**1.6.1**
- Fixed: sorting by Disenchant profit showed the vendor profit for items that can't be disenchanted. They now show N/A.

**1.6.0**
- New sorts: **Disenchant profit** and **Vendor profit**, from most profit to the biggest loss.
- The recipe panel shows both profits, and the breakdown lists each disenchanting result with its chance and value.

**1.5.1**
- Fixed: clicking some crafters outside your guild whispered "Name-SomethingRealm" and failed. Whispers now use the name alone.

**1.5.0**
- New filters: recipes you know and don't know, and the rarity of the item a recipe makes.
- New sorting: by skill to learn, recipe price, cost to craft and rarity, with or without categories.
- The recipe panel shows what the recipe costs to buy at the auction house and from vendors (including other currencies), where it's learned, and the skill needed.

**1.4.5**
- Categories can now be folded while searching.

**1.4.4**
- Searching for a stat now finds foods and potions whose stats are only in their "Use:" text, for example `spirit` finding Goblin Deviled Clams.

**1.4.3**
- Added the CurseForge project ID.

**1.4.2**
- New **List All** button on a recipe (List All Enchanters, List All Tailors...) to go back to everyone with the profession.

**1.4.1**
- Opening the profession of a crafter outside your guild also looks up their guild.
- Fixed: clicking quickly through crafters could save one person's recipes under another person.

**1.4.0**
- Crafters who don't use the addon: profession links in chat are remembered, and guild members without the addon are read from the game's guild profession list.
- Crafters outside your guild appear in blue and are shared with guild mates who use the addon.
- Only crafters on your ruleset and faction are shown.
- The recipe list says which filter or search is hiding recipes when it's empty.

**1.3.0**
- New minimap button.
- Recipe lists are shared much faster.
- Uses far less memory in large guilds.

**1.2.1**
- Fixed: a profession could show every recipe under "Other" when a guild mate's recipe list didn't reach you.
- Fixed: some recipes showed a placeholder icon.

**1.2.0**
- To Craft and Profit, using Auctionator prices.

**1.1.0**
- Search also finds recipes by their tooltip text.

**1.0.0**
- First release.

## Credits

Made by MendeleevForever. Uses the Ace3 libraries (AceComm, AceSerializer, CallbackHandler, LibStub), LibCompress, LibDataBroker and LibDBIcon; their licences are in the `Libs` folder.
