#!/bin/bash
# Patches the Godot-generated service worker to not intercept WebSocket requests.
# Run after every `godot --export-release "Web" ...`
# Root cause: Godot's service worker intercepts ALL fetch events (including WebSocket)
# and tries to add COEP/COOP headers via fetch(), which breaks WebSocket upgrade.

SW_FILE="${1:-export/web/index.service.worker.js}"

if [ ! -f "$SW_FILE" ]; then
    echo "Error: $SW_FILE not found"
    exit 1
fi

# Add WebSocket bypass at the start of the fetch handler
python3 -c "
import re, time
with open('$SW_FILE', 'r') as f:
    content = f.read()

# Skip if already patched
if 'Skip WebSocket' in content:
    print('Already patched')
    exit(0)

old = \"(event) => {\\n\\t\\tconst isNavigate = event.request.mode === 'navigate';\"
new = '''(event) => {
\t\t// Skip WebSocket requests — service worker cannot proxy them
\t\tif (event.request.url.includes('/ws') || event.request.headers.get('upgrade') === 'websocket') {
\t\t\treturn;
\t\t}
\t\tconst isNavigate = event.request.mode === 'navigate';'''

result = content.replace(old, new, 1)

# Bump cache version to force update
result = re.sub(r\"const CACHE_VERSION = '[^']*'\", f\"const CACHE_VERSION = '{int(time.time())}|ws-fix'\", result)

with open('$SW_FILE', 'w') as f:
    f.write(result)
print('Patched successfully')
"
