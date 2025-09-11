import os
from pathlib import Path

def _get_icon_path(icon_name: str) -> str:
    """アイコンファイルのパスを取得"""
    current_dir = Path(__file__).parent
    icon_path = current_dir / "icons" / f"{icon_name}.svg"
    return str(icon_path)

def _port_from_env(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except Exception:
        return default

def get_servers():
    return {
        "studio": {
            "command": [
                "studio",
                "--port",
                "{port}",
                "--base-url",
                "/studio"
            ],
            "new_browser_tab": True,
            "absolute_url": True,
            "launcher_entry": {
                "title": "Studio",
                "category": "Notebook",
                "enabled": True,
            },
        },
        "comfyui": {
            "command": [
                "python",
                "/opt/app/ComfyUI/main.py",
                "--listen",
                "127.0.0.1",
                "--port",
                "{port}"
            ],
            "timeout": 30,
            "new_browser_tab": True,
            "absolute_url": False,
            "launcher_entry": {
                "title": "ComfyUI",
                "category": "Notebook",
                "icon_path": _get_icon_path("comfyui"),
                "enabled": True,
            },
        },
        "filebrowser": {
            "command": [
                "filebrowser",
                "--address",
                "127.0.0.1",
                "--port",
                "{port}",
                "--root",
                "/storage/workspace",
                "--database",
                "/storage/system/filebrowser/filebrowser.db",
                "--baseurl",
                "/filebrowser"
            ],
            "new_browser_tab": True,
            "absolute_url": True,
            "launcher_entry": {
                "title": "Filebrowser",
                "category": "Notebook",
                "icon_path": _get_icon_path("filebrowser"),
                "enabled": True,
            },
        },
    }

def get_studio_config():
    servers = get_servers()
    return servers["studio"]

def get_comfyui_config():
    servers = get_servers()
    return servers["comfyui"]

def get_filebrowser_config():
    servers = get_servers()
    return servers["filebrowser"]
