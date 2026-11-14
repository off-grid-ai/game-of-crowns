// Low plants in the wind, cut out by their texture's alpha (countryside.gd's crop cards): plant_wind.gdshaderinc.
shader_type spatial;
render_mode cull_disabled;
#define CUT
#include "res://scripts/plant_wind.gdshaderinc"
