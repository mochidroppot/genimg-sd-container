import { app } from "../../scripts/app.js";

/**
 * ComfyUI ProxyFix Extension - Frontend
 * 
 * This extension fixes the URL encoding issue when ComfyUI is accessed through 
 * jupyter-server-proxy or other reverse proxies that decode URL-encoded slashes.
 * 
 * Problem: 
 * - ComfyUI saves workflows with path like "workflows/filename.json"
 * - When URL-encoded as "workflows%2Ffilename.json", jupyter-proxy-server 
 *   decodes it back to "workflows/filename.json"
 * - This causes routing issues
 * 
 * Solution:
 * - Replace "workflows/" with "workflows__SLASH__" in all userdata API calls
 * - The __SLASH__ marker is unique and won't conflict with user filenames
 * - Backend middleware converts it back to "workflows/" before processing
 */

// Unique separator that users are unlikely to use in filenames
const SLASH_REPLACEMENT = '__SLASH__';

app.registerExtension({
    name: "ComfyUI.ProxyFix.WorkflowSlash",

    async setup() {
        console.log('[ProxyFix] Initializing workflow slash fix extension...');
        console.log(`[ProxyFix] Using separator: ${SLASH_REPLACEMENT}`);

        // Store the original fetch function
        const originalFetch = window.fetch;

        // Override window.fetch to intercept API calls
        window.fetch = function(...args) {
            let [url, options] = args;

            // Only process string URLs (not Request objects)
            if (typeof url === 'string') {
                // Check if this is a userdata API call
                if (url.includes('/api/userdata/') || url.includes('/userdata/')) {
                    const originalUrl = url;

                    // Replace workflows/ with workflows__SLASH__ in the URL
                    // This handles both encoded (%2F) and unencoded (/) slashes
                    url = url
                        .replace(/\/workflows\//g, `/workflows${SLASH_REPLACEMENT}`)
                        .replace(/workflows%2F/gi, `workflows${SLASH_REPLACEMENT}`)
                        .replace(/workflows%252F/gi, `workflows${SLASH_REPLACEMENT}`); // Double-encoded

                    if (url !== originalUrl) {
                        console.log('[ProxyFix] Fixed workflow path:', {
                            original: originalUrl,
                            fixed: url
                        });
                    }
                }
            }

            // Call the original fetch with potentially modified URL
            return originalFetch(url, options);
        };

        console.log('[ProxyFix] Workflow slash fix extension loaded successfully');
    }
});
