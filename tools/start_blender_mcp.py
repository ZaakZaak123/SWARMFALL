"""Start the installed local Blender bridge without changing user preferences."""
import addon_utils
import bpy

addon_utils.enable("blender_mcp", default_set=False)
if not getattr(bpy.context.scene, "blendermcp_server_running", False):
    bpy.ops.blendermcp.start_server()
