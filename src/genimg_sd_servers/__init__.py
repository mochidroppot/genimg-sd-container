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
    comfy_port = _port_from_env("COMFYUI_PORT", 8188)
    fb_port = _port_from_env("FILEBROWSER_PORT", 8085)
    # command/timeout は省略（プロセス起動はせず、リンク遷移のみ）
    return {
        "comfyui": {
            "port": comfy_port,
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
            "port": fb_port,
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

def get_comfyui_config():
    servers = get_servers()
    return servers["comfyui"]

def get_filebrowser_config():
    servers = get_servers()
    return servers["filebrowser"]
