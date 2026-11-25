# Consumable Bar

Consumable Bar is a movable bar of buttons for the best food, water, bandage, potions and healthstone in your bags. It is made for World of Warcraft Forever and pairs with [Buff Bar](https://github.com/MechanicalFerret/wowf-buff-bar).

## Buttons

Food, Water, Bandage, Healing Potion, Mana Potion, Rejuvenation Potion and Healthstone.

- Each button uses the strongest item in your bags that your level allows. Amounts are read from item tooltips.
- Mage conjured food and water can be preferred, and Well Fed food can win ties. Both are options.
- When items are equal, the smaller stack is used first. You can switch this to the larger stack.
- Warriors and Rogues do not get Water or Mana Potion buttons.
- Warlocks get a tinted Create Healthstone button when they have no healthstone.
- Forsaken (Cannibalize) and Trolls (Rapid Regeneration) get a racial button after the Healthstone.

## Settings

Open them from Game Menu > Options > AddOns > Consumable Bar, or with `/cbar`. Hover an option for a description. The bar grows left or right from a fixed edge, and can be moved by unlocking it or in Edit Mode.

## Commands

- `/cbar`: open settings
- `/cbar unlock` and `/cbar lock`: unlock or lock the bar for moving
- `/cbar reset`: reset the bar position
- `/cbar debug`: print what the bar found in your bags

## Notes

- The bar does not update during combat. It catches up when combat ends, and using a button in combat refreshes that button.
- Items are detected from English tooltip text, so the addon only works on an English client.

## Installation

### WoWUp
1. Open WoWUp and select the World of Warcraft Forever client.
2. Go to **Get Addons** and click **Install from URL**.
3. Paste `https://github.com/MechanicalFerret/wowf-consumable-bar` and click **Install**.

WoWUp will then update the addon for you when a new release is published.

### Manual
1. Download the latest zip from the [Releases](https://github.com/MechanicalFerret/wowf-consumable-bar/releases) page.
2. Extract it so the folder is named `ConsumableBar` and sits inside `World of Warcraft/_forever_/Interface/AddOns`.
3. Restart the game, or run `/reload` if it is already open.
