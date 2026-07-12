# AEONS — icon art drop folder

The UI shows an "IMG" placeholder box wherever a PNG is missing here.
Drop a file with the matching name and it appears automatically (no code
changes). Suggested size: 64×64 (128×192 for `event_*`, wide for `logo`).

| Pattern | Used for | Examples |
|---|---|---|
| `logo.png` | main-menu title | — |
| `res_<id>.png` | top-bar resources | `res_food`, `res_materials`, `res_gold`, `res_influence`, `res_coal`, `res_oil`, `res_circuits` |
| `tech_<id>.png` | research option cards | `tech_agriculture`, `tech_bronzeWorking`, … (288 ids in `data/techs.js`) |
| `biome_<id>.png` | tile panel header | `biome_grassland`, `biome_desert`, … (ids in `data/biomes.js`) |
| `building_<id>.png` | slot details | `building_farm`, `building_mine`, … (ids in `data/buildings.js`) |
| `event_<id>.png` | event popups | `event_drought`, `event_goldenAge`, … (ids in `data/events.js`) |
| `perk_<id>.png` | age-up perk picks | `perk_fertileCrescent`, … (ids in `data/perks.js`) |
| `city_portrait.png` | city panel | — |
