# Consumable Bar

A bar of clickable buttons for your best Food, Water, Bandage, Healing Potion, Mana Potion, Rejuvenation Potion and Healthstone.

## Features
- Picks the strongest item in your bags that your level allows (amounts read from tooltips).
- Option to always prefer Mage conjured food and water. Well Fed food wins ties.
- Warlocks see a tinted Create Healthstone button when they have no healthstone.
- Forsaken (Cannibalize) and Trolls (Rapid Regeneration) get a racial button after the Healthstone.
- Grows left or right from a fixed anchor edge.
- Movable in Edit Mode (blue highlight, settings dialog when selected) or by unlocking the bar.
- Settings: Game Menu > Options > AddOns > Consumable Bar.

## Commands
- `/cbar` open settings
- `/cbar unlock` / `/cbar lock`
- `/cbar reset` reset position
- `/cbar debug` print what the bar found in your bags

## Notes
- Nothing is scanned or updated in combat; the bar catches up when combat ends. Using a bar button in combat refreshes just that button.
- Item detection reads English tooltip text.

## Install
Copy the folder to `Interface/AddOns/ConsumableBar`.
