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
from aiohttp import web

# Tell ComfyUI where to find our web extension files
WEB_DIRECTORY = "./web"

# ComfyUI requires these exports even if we don't define any custom nodes
NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}

# Unique separator that matches the frontend (must be identical)
SLASH_REPLACEMENT = '__SLASH__'

# Debug mode: set environment variable DEBUG_PROXYFIX=1 to enable verbose logging
DEBUG = os.environ.get('DEBUG_PROXYFIX', '').lower() in ('1', 'true', 'yes')


def _log(message):
    """Log message if debug mode is enabled"""
    if DEBUG:
        print(f"[ComfyUI-ProxyFix] {message}")


def convert_workflow_path_back(path):
    """
    Convert workflows__SLASH__ back to workflows/ in the path.

    Examples:
        'workflows__SLASH__test.json' -> 'workflows/test.json'
        'userdata/workflows__SLASH__my_flow.json' -> 'userdata/workflows/my_flow.json'
    """
    if SLASH_REPLACEMENT in path:
        return path.replace(f'workflows{SLASH_REPLACEMENT}', 'workflows/')
    return path


@web.middleware
async def proxy_fix_middleware(request, handler):
    """
    aiohttp middleware to convert workflows__SLASH__ back to workflows/ in request paths.
    """
    original_path = str(request.rel_url.path) if hasattr(request.rel_url, 'path') else request.path

    # Only process userdata requests that contain workflows__SLASH__
    if '/userdata/' in original_path and SLASH_REPLACEMENT in original_path:
        _log(f"Processing request: {original_path}")
        
        # Wrap handler to modify match_info after routing
        async def fixed_handler(req):
            from aiohttp.web_urldispatcher import MatchInfoError
            
            # Check if routing was successful (not a 404)
            if not isinstance(req.match_info, MatchInfoError):
                # Convert all match_info values containing __SLASH__
                for key in list(req.match_info.keys()):
                    value = req.match_info[key]
                    if isinstance(value, str) and SLASH_REPLACEMENT in value:
                        new_value = convert_workflow_path_back(value)
                        _log(f"Converting match_info['{key}']: {value} -> {new_value}")
                        
                        # Update match_info
                        try:
                            req.match_info[key] = new_value
                        except Exception as e:
                            _log(f"Error updating match_info: {e}")
            
            # Call the actual handler
            return await handler(req)
        
        return await fixed_handler(request)

    # For non-userdata requests, process normally
    return await handler(request)


def apply_middleware():
    """
    Apply the proxy fix middleware to the ComfyUI server.
    """
    try:
        import server

        # Get the PromptServer instance
        if hasattr(server, 'PromptServer') and hasattr(server.PromptServer, 'instance'):
            prompt_server = server.PromptServer.instance

            if prompt_server is not None and hasattr(prompt_server, 'app'):
                app = prompt_server.app

                # Apply middleware if not already applied
                if proxy_fix_middleware not in app.middlewares:
                    app.middlewares.insert(0, proxy_fix_middleware)
                    print("[ComfyUI-ProxyFix] Middleware applied successfully")
                    return True
                else:
                    _log("Middleware already applied")
                    return True

        _log("Warning: Could not find PromptServer instance")
        return False

    except ImportError:
        _log("server module not found (might load later)")
        return False
    except Exception as e:
        print(f"[ComfyUI-ProxyFix] Error applying middleware: {e}")
        return False


# Try to apply middleware immediately
middleware_applied = apply_middleware()

if not middleware_applied:
    # Delay initialization to ensure ComfyUI server is loaded
    import threading
    import time

    def delayed_init():
        """Retry applying middleware after a delay"""
        max_retries = 3
        retry_delay = 1

        for attempt in range(max_retries):
            time.sleep(retry_delay)
            _log(f"Retry {attempt + 1}/{max_retries}: Attempting to apply middleware...")

            if apply_middleware():
                print("[ComfyUI-ProxyFix] Middleware applied after delayed retry")
                return

        print("[ComfyUI-ProxyFix] Warning: Failed to apply middleware after all retries")
        print("[ComfyUI-ProxyFix] Frontend fix will still work for most cases")

    thread = threading.Thread(target=delayed_init, daemon=True)
    thread.start()

# Print confirmation that the extension is loaded
print("[ComfyUI-ProxyFix] Extension loaded")
if DEBUG:
    print(f"[ComfyUI-ProxyFix] Debug mode enabled")
    print(f"[ComfyUI-ProxyFix] Web directory: {WEB_DIRECTORY}")
    print(f"[ComfyUI-ProxyFix] Using separator: {SLASH_REPLACEMENT}")

__all__ = ['NODE_CLASS_MAPPINGS', 'NODE_DISPLAY_NAME_MAPPINGS', 'WEB_DIRECTORY']