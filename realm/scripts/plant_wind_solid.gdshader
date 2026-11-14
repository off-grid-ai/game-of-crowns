// Low plants in the wind, whole meshes with no cut-out (countryside.gd's Meshy grass and flower tufts, opaque):
// no alpha test, so the depth test throws away hidden grass before it is shaded (supervisor cyclevis, fps:
// every tuft pixel went through the discard path). plant_wind.gdshaderinc.
shader_type spatial;
render_mode cull_disabled;
#include "res://scripts/plant_wind.gdshaderinc"
