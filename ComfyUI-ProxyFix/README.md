# ComfyUI Proxy Fix Extension

This extension fixes URL encoding issues that occur when ComfyUI is accessed through reverse proxies like jupyter-server-proxy.

## Problem

When ComfyUI is accessed through jupyter-server-proxy, workflow saving fails with a 405 error because:

1. ComfyUI frontend sends: `/api/userdata/workflows%2Flora.json`
2. jupyter-server-proxy decodes: `/api/userdata/workflows/lora.json`
3. ComfyUI expects: `/api/userdata/workflows%2Flora.json`
4. Result: 405 Method Not Allowed error

## Solution

This extension automatically patches the ComfyUI frontend to use double-encoded paths:

1. ComfyUI frontend sends: `/api/userdata/workflows%252Flora.json`
2. jupyter-server-proxy decodes: `/api/userdata/workflows%2Flora.json`
3. ComfyUI receives: `/api/userdata/workflows%2Flora.json` ✅

## Installation

### Method 1: Install as ComfyUI Extension

```bash
cd ComfyUI/custom_nodes
git clone https://github.com/your-repo/ComfyUI-ProxyFix.git
cd ComfyUI-ProxyFix
pip install -e .
```

### Method 2: Install via ComfyUI Manager

1. Open ComfyUI
2. Click on "Manager" button
3. Search for "ProxyFix"
4. Install the extension

## Usage

The extension automatically applies the fix when ComfyUI starts. No additional configuration is required.

## Testing

To verify the fix is working:

1. Open ComfyUI through jupyter-server-proxy
2. Create a workflow
3. Try to save it - it should work without 405 errors

## Compatibility

- ComfyUI 0.3.57+
- jupyter-server-proxy
- Other reverse proxies that decode URL-encoded paths

## License

MIT License
