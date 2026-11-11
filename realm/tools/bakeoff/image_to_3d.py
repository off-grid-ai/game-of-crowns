"""Image-to-3D for the art bake-off, through the free Hugging Face Spaces (no local GPU, no disk for weights).
   python3 image_to_3d.py <trellis|trellis2|hunyuan> <concept.png> <out.glb>
Needs gradio_client (pip). Anonymous use gets about 2 GPU-minutes a day per IP (one model); set HF_TOKEN
(a free Hugging Face account) for more, or a PRO account for ~25 min a day. Each model takes 60-135 s of quota."""
import shutil
import sys
import time

from gradio_client import Client as _Client, handle_file
from huggingface_hub import get_token


def Client(space):  # the logged-in quota: HF_TOKEN or ~/.cache/huggingface/token
    return _Client(space, token=get_token())

route, src, out = sys.argv[1], sys.argv[2], sys.argv[3]
t = time.time()
if route == "trellis":
    c = Client("trellis-community/TRELLIS")
    try:
        c.predict(api_name="/start_session")
    except Exception as e:  # older builds have no session hook
        print("start_session:", e)
    img = c.predict(handle_file(src), api_name="/preprocess_image")
    r = c.predict(image=handle_file(img), multiimages=[], seed=1, ss_guidance_strength=7.5, ss_sampling_steps=12,
                  slat_guidance_strength=3.0, slat_sampling_steps=12, multiimage_algo="stochastic",
                  mesh_simplify=0.9, texture_size=2048, api_name="/generate_and_extract_glb")
    glb = r[2] or r[1]
elif route == "trellis2":
    c = Client("microsoft/TRELLIS.2")
    c.predict(api_name="/start_session")
    img = c.predict(handle_file(src), api_name="/preprocess_image")
    c.predict(image=handle_file(img), seed=1, resolution="1024", api_name="/image_to_3d")
    glb = c.predict(decimation_target=200000, texture_size=2048, api_name="/extract_glb")[1]
elif route == "hunyuan":
    c = Client("tencent/Hunyuan3D-2")
    r = c.predict(caption=None, image=handle_file(src), mv_image_front=None, mv_image_back=None, mv_image_left=None,
                  mv_image_right=None, steps=30, guidance_scale=5.0, seed=1234, octree_resolution=256,
                  check_box_rembg=True, num_chunks=8000, randomize_seed=False, api_name="/generation_all")
    glb = r[1] or r[0]
else:
    sys.exit("route: trellis | trellis2 | hunyuan")
shutil.copy(glb, out)
print("ok", out, round(time.time() - t), "s")
