"""
ComfyUI ProxyFix Extension

This extension fixes the URL encoding issue when ComfyUI is accessed through 
jupyter-server-proxy or other reverse proxies that decode URL-encoded slashes.

The fix works in two parts:
1. Frontend (JavaScript): Converts workflows/ to workflows__SLASH__ in API calls
2. Backend (Python): Converts workflows__SLASH__ back to workflows/ before processing

The __SLASH__ separator is unique and won't conflict with user filenames.
"""

import os
import re
from aiohttp import web

# Tell ComfyUI where to find our web extension files
# This is critical - without this, the JavaScript won't be loaded
WEB_DIRECTORY = "./web"

# ComfyUI requires these exports even if we don't define any custom nodes
NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}

# Unique separator that matches the frontend (must be identical)
SLASH_REPLACEMENT = '__SLASH__'


def convert_workflow_path_back(path):
    """
    Convert workflows__SLASH__ back to workflows/ in the path.

    This reverses the frontend transformation, ensuring files are saved
    in the correct workflows/ directory as users expect.

    The __SLASH__ marker is unique and won't conflict with underscores
    in user filenames (e.g., my_workflow.json).

    Examples:
        'workflows__SLASH__test.json' -> 'workflows/test.json'
        'userdata/workflows__SLASH__my_flow.json' -> 'userdata/workflows/my_flow.json'
        'workflows__SLASH__my_workflow_v2.json' -> 'workflows/my_workflow_v2.json' (safe!)
    """
    # Replace workflows__SLASH__ with workflows/
    if SLASH_REPLACEMENT in path:
        # Use replace() to handle all occurrences, though typically there's only one
        path = path.replace(f'workflows{SLASH_REPLACEMENT}', 'workflows/')
        return path
    return path


@web.middleware
async def proxy_fix_middleware(request, handler):
    """
    aiohttp middleware to convert workflows__SLASH__ back to workflows/ in request paths.

    This middleware intercepts all requests to /userdata/ endpoints and converts
    the frontend's workflows__SLASH__ transformation back to workflows/ so that ComfyUI
    can process the request normally.
    
    We need to modify the request's match_info AFTER routing but BEFORE the handler.
    Since middleware runs before routing, we wrap the handler to intercept after routing.
    """
    original_path = request.path

    # Only process userdata requests that contain workflows__SLASH__
    if '/userdata/' in original_path and SLASH_REPLACEMENT in original_path:
        print(f"[ComfyUI-ProxyFix] Detected __SLASH__ in path: {original_path}")
        
        # Wrap the handler to modify match_info after routing
        async def wrapped_handler(req):
            # At this point, routing has happened and match_info is populated
            print(f"[ComfyUI-ProxyFix] match_info before: {dict(req.match_info)}")
            
            # Convert all match_info values that contain __SLASH__
            modified = False
            for key, value in list(req.match_info.items()):
                if isinstance(value, str) and SLASH_REPLACEMENT in value:
                    new_value = convert_workflow_path_back(value)
                    req.match_info[key] = new_value
                    print(f"[ComfyUI-ProxyFix] Converted match_info['{key}']: {value} -> {new_value}")
                    modified = True
            
            if modified:
                print(f"[ComfyUI-ProxyFix] match_info after: {dict(req.match_info)}")
            
            # Call the original handler with modified match_info
            return await handler(req)
        
        return await wrapped_handler(request)

    # For requests that don't need path conversion, process normally
    return await handler(request)


def apply_middleware():
    """
    Apply the proxy fix middleware to the ComfyUI server.

    This function is called during ComfyUI initialization to inject our
    middleware into the aiohttp application.
    """
    try:
        import server

        # Get the PromptServer instance
        if hasattr(server, 'PromptServer') and hasattr(server.PromptServer, 'instance'):
            prompt_server = server.PromptServer.instance

            if prompt_server is not None and hasattr(prompt_server, 'app'):
                # Get the aiohttp app
                app = prompt_server.app

                # Check if middleware is already applied
                if proxy_fix_middleware not in app.middlewares:
                    # Insert at the beginning to catch requests early
                    app.middlewares.insert(0, proxy_fix_middleware)
                    print("[ComfyUI-ProxyFix] Backend middleware applied successfully")
                    return True
                else:
                    print("[ComfyUI-ProxyFix] Backend middleware already applied")
                    return True

        print("[ComfyUI-ProxyFix] Warning: Could not find PromptServer instance")
        return False

    except ImportError:
        print("[ComfyUI-ProxyFix] Warning: server module not found (might load later)")
        return False
    except Exception as e:
        print(f"[ComfyUI-ProxyFix] Error applying backend middleware: {e}")
        return False


# Try to apply middleware immediately
# If server is not loaded yet, we'll try again in a delayed thread
middleware_applied = apply_middleware()

if not middleware_applied:
    # Delay initialization to ensure ComfyUI server is loaded
    import threading
    import time

    def delayed_init():
        """Retry applying middleware after a delay"""
        max_retries = 5
        retry_delay = 2

        for attempt in range(max_retries):
            time.sleep(retry_delay)
            print(f"[ComfyUI-ProxyFix] Retry {attempt + 1}/{max_retries}: Attempting to apply backend middleware...")

            if apply_middleware():
                print("[ComfyUI-ProxyFix] Backend middleware applied after delayed retry")
                return

        print("[ComfyUI-ProxyFix] Warning: Failed to apply backend middleware after all retries")
        print("[ComfyUI-ProxyFix] Frontend fix will still work, but workflows may be saved with 'workflows_' prefix")

    thread = threading.Thread(target=delayed_init, daemon=True)
    thread.start()

# Print confirmation that the extension is loaded
print("[ComfyUI-ProxyFix] Extension loaded successfully")
print(f"[ComfyUI-ProxyFix] Web directory: {WEB_DIRECTORY}")
print(f"[ComfyUI-ProxyFix] Using separator: {SLASH_REPLACEMENT}")
print(f"[ComfyUI-ProxyFix] Frontend: workflows/ -> workflows{SLASH_REPLACEMENT} (in URLs)")
print(f"[ComfyUI-ProxyFix] Backend: workflows{SLASH_REPLACEMENT} -> workflows/ (before processing)")

__all__ = ['NODE_CLASS_MAPPINGS', 'NODE_DISPLAY_NAME_MAPPINGS', 'WEB_DIRECTORY']
