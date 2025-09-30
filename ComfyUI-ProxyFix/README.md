# ComfyUI Proxy Fix Extension
# ComfyUI ProxyFix Extension

This extension fixes URL encoding issues when ComfyUI is accessed through reverse proxies like `jupyter-server-proxy`.

## Problem

When ComfyUI saves workflows, it uses paths like `workflows/filename.json`. This causes issues when:

1. The frontend URL-encodes the path as `workflows%2Ffilename.json`
2. `jupyter-server-proxy` automatically decodes `%2F` back to `/`
3. ComfyUI's router receives `workflows/filename.json` and interprets it as a subdirectory
4. API calls fail with routing errors

## Solution

This extension applies fixes at both frontend and backend:

### Frontend (JavaScript)
- Intercepts all `fetch()` API calls to `/api/userdata/`
- Replaces `workflows/` with `workflows_` before sending requests
- Keeps the path flat, avoiding URL encoding issues entirely

### Backend (Python)
- Provides fallback path normalization for any server-side routing
- Ensures consistent behavior across different proxy configurations

## Installation

This extension is automatically installed as a ComfyUI custom node in the Docker image.

Files:
- `web/fix-workflow-slash.js` - Frontend extension
- `__init__.py` - Backend middleware (fallback)

## Usage

No configuration needed. The extension activates automatically when ComfyUI starts.

You can verify it's working by checking the browser console:
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
