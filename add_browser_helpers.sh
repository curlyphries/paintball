#!/bin/bash
# Adds browser helper scripts to exported HTML

cd "$(dirname "$0")/export/web" || exit 1

# Create unfocus button script
cat > unfocus_button.js << 'JSEOF'
(function() {
    function addButton() {
        var div = document.createElement('div');
        div.id = 'browser-controls';
        div.innerHTML = '<span style="color:#fff;font-size:13px;font-family:sans-serif;">⌨️ Enable browser shortcuts:</span><button id="unfocus-btn" style="background:#4af;border:none;padding:6px 12px;border-radius:4px;color:#000;font-weight:bold;cursor:pointer;margin:0 8px;">Click here</button><span style="color:#aaa;font-size:11px;font-family:sans-serif;">Then use Ctrl+F5, Ctrl+Plus/Minus</span>';
        div.style.cssText = 'position:fixed;top:10px;right:10px;z-index:99999;background:rgba(30,30,40,0.95);padding:10px 15px;border-radius:6px;border:1px solid #4af;display:flex;gap:8px;align-items:center;';
        
        document.body.appendChild(div);
        
        document.getElementById('unfocus-btn').onclick = function() {
            var canvas = document.getElementById('canvas');
            if (canvas) canvas.blur();
            document.body.focus();
            this.textContent = '✓ Done';
            setTimeout(function() { document.getElementById('unfocus-btn').textContent = 'Click here'; }, 2000);
        };
    }
    
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', addButton);
    } else {
        addButton();
    }
})();
JSEOF

# Add to index.html if not already there
if ! grep -q "unfocus_button.js" index.html; then
    sed -i 's/<script src="force_browser_shortcuts.js"><\/script>/<script src="force_browser_shortcuts.js"><\/script>\n        <script src="unfocus_button.js"><\/script>/' index.html
fi

echo "Browser helpers added to export/web/"
