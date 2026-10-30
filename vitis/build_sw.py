# Build a standalone platform + hello app from the Vivado XSA.
# Run from CSCI497I_Base_Cora/vitis:   vitis -s build_sw.py
import os
import shutil
import vitis

here   = os.path.dirname(os.path.abspath(__file__))
repo   = os.path.abspath(os.path.join(here, ".."))
xsa    = os.path.join(repo, "fpga", "project_main", "project_main.xsa")
src    = here
ws     = os.path.join(here, "ws")

plat_name = "cora_plat"
app_name  = "hello"
cpu       = "ps7_cortexa9_0"
domain    = "standalone_" + cpu

if not os.path.isfile(xsa):
    raise FileNotFoundError(xsa)

if os.path.exists(ws):
    shutil.rmtree(ws)
os.makedirs(ws)

client = vitis.create_client()
client.set_workspace(path=ws)

platform = client.create_platform_component(
    name=plat_name,
    hw_design=xsa,
    os="standalone",
    cpu=cpu,
    domain_name=domain,
)
platform.build()

xpfm = os.path.join(ws, plat_name, "export", plat_name, plat_name + ".xpfm")

app = client.create_app_component(
    name=app_name,
    platform=xpfm,
    domain=domain,
)
app.import_files(from_loc=src, files=["main.c"], dest_dir_in_cmp="src")
app.build()

vitis.dispose()
