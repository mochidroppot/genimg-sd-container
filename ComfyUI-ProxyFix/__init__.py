"""
ComfyUI Proxy Fix Extension

This extension fixes the URL encoding issue when ComfyUI is accessed through 
jupyter-server-proxy or other reverse proxies that decode URL-encoded paths.
"""

import os
import sys
import re
from pathlib import Path

class ProxyFixExtension:
    """Extension to fix proxy-related URL encoding issues"""
    
    def __init__(self):
        self.name = "ProxyFix"
        self.version = "1.0.0"
        self.description = "Fixes URL encoding issues with reverse proxies"
    
    def apply_frontend_patch(self):
        """Apply frontend patches to fix URL encoding"""
        try:
            # Find ComfyUI frontend package
            import pkg_resources
            frontend_path = pkg_resources.get_distribution('comfyui-frontend-package').location
            
            js_files_patched = 0
            for root, dirs, files in os.walk(frontend_path):
                for file in files:
                    if file.endswith('.js'):
                        file_path = os.path.join(root, file)
                        try:
                            with open(file_path, 'r', encoding='utf-8') as f:
                                content = f.read()
                            
                            # Replace workflows/ with double-encoded version
                            if 'workflows/' in content:
                                modified_content = content.replace('workflows/', 'workflows%252F')
                                
                                with open(file_path, 'w', encoding='utf-8') as f:
                                    f.write(modified_content)
                                
                                js_files_patched += 1
                                print(f"[ProxyFix] Patched: {file_path}")
                                
                        except Exception as e:
                            print(f"[ProxyFix] Error processing {file_path}: {e}")
            
            print(f"[ProxyFix] Total files patched: {js_files_patched}")
            return js_files_patched > 0
            
        except Exception as e:
            print(f"[ProxyFix] Failed to apply frontend patch: {e}")
            return False

# Global instance
proxy_fix = ProxyFixExtension()

# Auto-apply patch on import
if __name__ != "__main__":
    proxy_fix.apply_frontend_patch()
