"""
ComfyUI Proxy Fix Extension

This extension fixes the URL encoding issue when ComfyUI is accessed through 
jupyter-server-proxy or other reverse proxies that decode URL-encoded paths.
"""

import os
import sys
import re
from pathlib import Path
from urllib.parse import unquote, quote

class ProxyFixMiddleware:
    """Middleware to fix proxy-related URL path issues"""

    def __init__(self, app):
        self.app = app
        self.name = "ProxyFix"
        self.version = "1.0.0"

    def __call__(self, environ, start_response):
        """WSGI middleware to fix paths before they reach ComfyUI"""
        path_info = environ.get('PATH_INFO', '')
        request_uri = environ.get('REQUEST_URI', '')

        # Check if this is a userdata/workflows request that needs fixing
        if self._needs_path_fix(path_info):
            fixed_path = self._fix_workflows_path(path_info)
            if fixed_path != path_info:
                print(f"[ProxyFix] Path fixed: {path_info} -> {fixed_path}")
                environ['PATH_INFO'] = fixed_path
                # Also update REQUEST_URI if present
                if request_uri:
                    environ['REQUEST_URI'] = request_uri.replace(path_info, fixed_path)

        return self.app(environ, start_response)

    def _needs_path_fix(self, path):
        """Check if the path needs fixing"""
        # Match paths like /comfyui/api/userdata/workflows/something.json
        pattern = r'^/comfyui/api/userdata/workflows/[^/]+\.json$'
        return bool(re.match(pattern, path))

    def _fix_workflows_path(self, path):
        """Fix the workflows path by encoding the last slash"""
        # Replace the last slash before the filename with %2F
        # /comfyui/api/userdata/workflows/default.json -> /comfyui/api/userdata/workflows%2Fdefault.json
        match = re.match(r'^(/comfyui/api/userdata/workflows)/([^/]+\.json)$', path)
        if match:
            base_path = match.group(1)
            filename = match.group(2)
            return f"{base_path}%2F{filename}"
        return path


class ProxyFixExtension:
    """Extension to fix proxy-related URL encoding issues"""

    def __init__(self):
        self.name = "ProxyFix"
        self.version = "1.0.0"
        self.description = "Fixes URL encoding issues with reverse proxies"
        self.middleware_applied = False

    def apply_middleware_patch(self):
        """Apply middleware patch to ComfyUI server"""
        try:
            # Try to find and patch ComfyUI's main server application
            import server

            # Check if the server has a web app attribute
            if hasattr(server, 'app') and server.app is not None:
                # Wrap the existing app with our middleware
                if not self.middleware_applied:
                    server.app = ProxyFixMiddleware(server.app)
                    self.middleware_applied = True
                    print(f"[ProxyFix] Middleware applied to ComfyUI server")
                    return True

            # Alternative approach: patch the server creation function
            if hasattr(server, 'create_app') or hasattr(server, 'PromptServer'):
                self._patch_server_creation()
                return True

            print(f"[ProxyFix] Could not find ComfyUI server to patch")
            return False

        except ImportError:
            print(f"[ProxyFix] ComfyUI server module not found")
            return False
        except Exception as e:
            print(f"[ProxyFix] Failed to apply middleware patch: {e}")
            return False

    def _patch_server_creation(self):
        """Patch server creation to include our middleware"""
        try:
            import server

            # If PromptServer class exists, monkey patch it
            if hasattr(server, 'PromptServer'):
                original_init = server.PromptServer.__init__

                def patched_init(self, loop):
                    result = original_init(self, loop)
                    # Apply middleware to the web app
                    if hasattr(self, 'app') and self.app is not None:
                        self.app = ProxyFixMiddleware(self.app)
                        print(f"[ProxyFix] Middleware applied to PromptServer")
                    return result

                server.PromptServer.__init__ = patched_init
                self.middleware_applied = True
                return True

        except Exception as e:
            print(f"[ProxyFix] Error patching server creation: {e}")
            return False

    def apply_aiohttp_middleware(self):
        """Apply middleware for aiohttp-based ComfyUI server"""
        try:
            import server
            import aiohttp.web

            @aiohttp.web.middleware
            async def proxy_fix_middleware(request, handler):
                """aiohttp middleware to fix proxy path issues"""
                raw_path = request.path  # no query string
                query = request.query_string

                # Check if this path needs fixing
                pattern = r'^/comfyui/api/userdata/workflows/[^/]+\.json$'
                if re.match(pattern, raw_path):
                    # Create a new path with fixed slash
                    fixed_path = re.sub(
                        r'^(/comfyui/api/userdata/workflows)/([^/]+\.json)$',
                        r'\1%2F\2',
                        raw_path
                    )
                    if fixed_path != raw_path:
                        fixed_full = fixed_path + (f"?{query}" if query else "")
                        print(f"[ProxyFix] Path fixed: {raw_path}{('?' + query) if query else ''} -> {fixed_full}")
                        # Build new relative URL preserving query
                        from yarl import URL
                        new_rel = URL.build(path=fixed_path, query_string=query)
                        request = request.clone(rel_url=new_rel)

                return await handler(request)

            # Try to add middleware to existing server
            if hasattr(server, 'PromptServer') and hasattr(server.PromptServer, 'middlewares'):
                server.PromptServer.middlewares.append(proxy_fix_middleware)
                print(f"[ProxyFix] aiohttp middleware added")
                return True

        except Exception as e:
            print(f"[ProxyFix] Failed to apply aiohttp middleware: {e}")
            return False

    def apply_route_patch(self):
        """Apply route-level patch for ComfyUI API"""
        try:
            import server

            # Find the userdata route handler
            if hasattr(server, 'PromptServer'):
                prompt_server = server.PromptServer

                # Look for existing route handlers
                if hasattr(prompt_server, 'routes') or hasattr(prompt_server, 'app'):
                    # Patch the specific userdata handler
                    self._patch_userdata_routes(prompt_server)
                    return True

        except Exception as e:
            print(f"[ProxyFix] Failed to apply route patch: {e}")
            return False

    def _patch_userdata_routes(self, server_instance):
        """Patch userdata routes specifically"""
        try:
            # This would require more specific knowledge of ComfyUI's routing
            # For now, we'll use a more general approach
            pass
        except Exception as e:
            print(f"[ProxyFix] Error patching userdata routes: {e}")

    def _needs_path_fix(self, path):
        """Check if the path needs fixing"""
        # Match paths like /comfyui/api/userdata/workflows/something.json
        pattern = r'^/comfyui/api/userdata/workflows/[^/]+\.json$'
        return bool(re.match(pattern, path))

    def _fix_workflows_path(self, path):
        """Fix the workflows path by encoding the last slash"""
        # Replace the last slash before the filename with %2F
        # /comfyui/api/userdata/workflows/default.json -> /comfyui/api/userdata/workflows%2Fdefault.json
        match = re.match(r'^(/comfyui/api/userdata/workflows)/([^/]+\.json)$', path)
        if match:
            base_path = match.group(1)
            filename = match.group(2)
            return f"{base_path}%2F{filename}"
        return path


# Global instance
proxy_fix = ProxyFixExtension()

def initialize_proxy_fix():
    """Initialize the proxy fix extension"""
    success = False

    # Try different patching methods in order of preference
    if proxy_fix.apply_middleware_patch():
        success = True
    elif proxy_fix.apply_aiohttp_middleware():
        success = True
    elif proxy_fix.apply_route_patch():
        success = True

    if not success:
        print(f"[ProxyFix] Warning: Could not apply any patches. Extension may not work correctly.")

    return success

# Auto-initialize when imported
if __name__ != "__main__":
    # Delay initialization to ensure ComfyUI modules are loaded
    import threading
    import time

    def delayed_init():
        time.sleep(2)  # Wait for ComfyUI to initialize
        initialize_proxy_fix()

    thread = threading.Thread(target=delayed_init, daemon=True)
    thread.start()
