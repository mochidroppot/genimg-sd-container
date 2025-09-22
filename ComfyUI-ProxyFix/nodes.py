"""
ComfyUI ProxyFix Nodes

This module provides the ComfyUI node interface for the ProxyFix extension.
It is designed to work both when installed as a Python package (ComfyUI_ProxyFix)
AND when placed directly under ComfyUI/custom_nodes.
"""

# Try to import from installed package first, then fallback to relative import when packaged
try:
    from ComfyUI_ProxyFix import proxy_fix, initialize_proxy_fix
except Exception:
    try:
        from . import proxy_fix, initialize_proxy_fix  # type: ignore
    except Exception:
        # Last resort: dynamic import from current file directory
        import importlib.util, os
        _here = os.path.dirname(os.path.abspath(__file__))
        _init_path = os.path.join(_here, "__init__.py")
        spec = importlib.util.spec_from_file_location("ComfyUI_ProxyFix_dynamic", _init_path)
        _mod = importlib.util.module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(_mod)
        proxy_fix = _mod.proxy_fix
        initialize_proxy_fix = _mod.initialize_proxy_fix

NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}

class ProxyFixStatusNode:
    """Node to display ProxyFix status and manually trigger fixes"""

    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "action": (["check_status", "reinitialize", "test_path"], {"default": "check_status"}),
                "test_path": ("STRING", {"default": "/comfyui/api/userdata/workflows/default.json"}),
            }
        }

    RETURN_TYPES = ("STRING",)
    FUNCTION = "execute"
    CATEGORY = "system/proxy"
    OUTPUT_NODE = True

    def execute(self, action, test_path):
        if action == "check_status":
            status = f"ProxyFix v{proxy_fix.version}\n"
            status += f"Middleware applied: {proxy_fix.middleware_applied}\n"
            status += f"Description: {proxy_fix.description}"
            return (status,)

        elif action == "reinitialize":
            success = initialize_proxy_fix()
            result = "Reinitialization successful" if success else "Reinitialization failed"
            return (result,)

        elif action == "test_path":
            if proxy_fix._needs_path_fix(test_path):
                fixed = proxy_fix._fix_workflows_path(test_path)
                result = f"Path needs fixing:\nOriginal: {test_path}\nFixed: {fixed}"
            else:
                result = f"Path doesn't need fixing: {test_path}"
            return (result,)

        return ("Unknown action",)

# Export for ComfyUI
__all__ = ['NODE_CLASS_MAPPINGS', 'NODE_DISPLAY_NAME_MAPPINGS']
