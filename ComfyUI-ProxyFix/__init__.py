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
import yarl
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

    This middleware wraps the handler to modify match_info after routing.
    """
    original_path = str(request.rel_url.path) if hasattr(request.rel_url, 'path') else request.path

    # Only process userdata requests that contain workflows__SLASH__
    if '/userdata/' in original_path and SLASH_REPLACEMENT in original_path:
        print(f"[ComfyUI-ProxyFix] Middleware: Detected __SLASH__ in path: {original_path}")
        
        # Wrap the handler to intercept after routing
        async def fixed_handler(req):
            # At this point, routing has occurred and match_info is populated
            print(f"[ComfyUI-ProxyFix] After routing, match_info BEFORE fix: {dict(req.match_info)}")
            
            # Convert all match_info values
            from aiohttp.web_urldispatcher import MatchInfoError
            
            # Check if routing was successful (not a 404)
            if not isinstance(req.match_info, MatchInfoError):
                for key in list(req.match_info.keys()):
                    value = req.match_info[key]
                    if isinstance(value, str) and SLASH_REPLACEMENT in value:
                        new_value = convert_workflow_path_back(value)
                        print(f"[ComfyUI-ProxyFix] Converting match_info['{key}']: {value} -> {new_value}")
                        
                        # Force update the match_info dictionary
                        # Try multiple methods to ensure it sticks
                        try:
                            # Method 1: Direct assignment
                            req.match_info[key] = new_value
                            
                            # Method 2: Update internal dict if it exists
                            if hasattr(req.match_info, '_match_dict'):
                                req.match_info._match_dict[key] = new_value
                            
                            # Method 3: Update via __setitem__ if available  
                            if hasattr(req.match_info, '__setitem__'):
                                req.match_info.__setitem__(key, new_value)
                                
                            print(f"[ComfyUI-ProxyFix] Successfully updated match_info['{key}']")
                        except Exception as e:
                            print(f"[ComfyUI-ProxyFix] Error updating match_info: {e}")
                
                print(f"[ComfyUI-ProxyFix] After routing, match_info AFTER fix: {dict(req.match_info)}")
            else:
                print(f"[ComfyUI-ProxyFix] Routing error occurred: {req.match_info}")
            
            # Call the actual handler
            return await handler(req)
        
        # Call our wrapped handler
        return await fixed_handler(request)

    # For non-userdata requests, process normally
    return await handler(request)


def wrap_userdata_routes(app):
    """
    Wrap the userdata route handlers to fix the __SLASH__ conversion.
    
    This directly wraps the handlers, which is more reliable than middleware
    for modifying route parameters.
    """
    wrapped_count = 0
    
    print(f"[ComfyUI-ProxyFix] Inspecting all routes in the app...")
    for route in app.router.routes():
        # Get route information
        try:
            route_info = route.get_info()
            route_path = str(route_info.get('path', route_info.get('formatter', '')))
            
            # Log all routes for debugging
            print(f"[ComfyUI-ProxyFix] Found route: {route_path} (type: {type(route).__name__})")
            
            # Check if this is a userdata route (check multiple patterns)
            is_userdata_route = (
                'userdata' in route_path or
                '/api/userdata' in route_path or
                hasattr(route, '_handler') and route._handler is not None
            )
            
            if is_userdata_route and hasattr(route, '_handler'):
                print(f"[ComfyUI-ProxyFix] Wrapping route: {route_path}")
                
                # Wrap the handler
                original_handler = route._handler
                
                def create_wrapped_handler(orig_handler):
                    async def wrapped_handler(request):
                        # Log the request
                        print(f"[ComfyUI-ProxyFix] Handler called for: {request.path}")
                        print(f"[ComfyUI-ProxyFix] match_info: {dict(request.match_info)}")
                        
                        # Check and convert match_info parameters
                        modified = False
                        for key, value in list(request.match_info.items()):
                            if isinstance(value, str) and SLASH_REPLACEMENT in value:
                                new_value = convert_workflow_path_back(value)
                                # Try to update match_info
                                try:
                                    # match_info is a MatchInfoMapping, try to modify it
                                    if hasattr(request.match_info, '_match_dict'):
                                        request.match_info._match_dict[key] = new_value
                                    request.match_info[key] = new_value
                                    modified = True
                                    print(f"[ComfyUI-ProxyFix] Converted {key}: {value} -> {new_value}")
                                except Exception as e:
                                    print(f"[ComfyUI-ProxyFix] Failed to modify match_info: {e}")
                        
                        if modified:
                            print(f"[ComfyUI-ProxyFix] Updated match_info: {dict(request.match_info)}")
                        
                        # Call original handler
                        return await orig_handler(request)
                    
                    return wrapped_handler
                
                # Apply the wrapper
                route._handler = create_wrapped_handler(original_handler)
                wrapped_count += 1
                
        except Exception as e:
            print(f"[ComfyUI-ProxyFix] Error inspecting route: {e}")
            continue
    
    print(f"[ComfyUI-ProxyFix] Wrapped {wrapped_count} routes")
    return wrapped_count > 0


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

                # Method 1: Apply middleware
                if proxy_fix_middleware not in app.middlewares:
                    # Insert at the beginning to catch requests early
                    app.middlewares.insert(0, proxy_fix_middleware)
                    print("[ComfyUI-ProxyFix] Backend middleware applied successfully")
                else:
                    print("[ComfyUI-ProxyFix] Backend middleware already applied")
                
                # Method 2: Wrap userdata route handlers directly
                wrap_userdata_routes(app)
                
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
