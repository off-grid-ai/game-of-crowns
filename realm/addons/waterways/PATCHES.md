# Local patches

Waterways is from https://github.com/Arnklit/Waterways, branch `godot4_5_1` (MIT).
Changes made for Game of Crowns, to carry over on any update:

- `river_manager.gd`: `_get` and `_property_get_revert` end with `return null`.
  Godot 4.7 refuses a function where not every path returns a value.
