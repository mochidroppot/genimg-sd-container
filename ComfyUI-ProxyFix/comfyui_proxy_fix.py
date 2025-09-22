"""
ComfyUI ProxyFix startup script

This script can be imported or executed to apply the proxy fix.
"""

import sys
import os
import importlib.util

def load_and_apply_proxy_fix():
    """Load and apply the proxy fix"""
    try:
        # Get the directory of this script
        script_dir = os.path.dirname(os.path.abspath(__file__))
        init_file = os.path.join(script_dir, '__init__.py')

        # Load the module
        spec = importlib.util.spec_from_file_location("proxy_fix_module", init_file)
        proxy_fix_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(proxy_fix_module)

        # Apply the fix
        return proxy_fix_module.initialize_proxy_fix()

    except Exception as e:
        print(f"Failed to load proxy fix: {e}")
        return False

if __name__ == "__main__":
    success = load_and_apply_proxy_fix()
    if success:
        print("ProxyFix applied successfully")
        sys.exit(0)
    else:
        print("ProxyFix failed to apply")
        sys.exit(1)
