# Step 16: Morphdom Integration

## What We're Building

Our LiveView currently uses `innerHTML` to update the page. This has
a major problem: it **destroys and recreates** all DOM elements, which:

- Loses input focus (user typing in a text box gets interrupted)
- Kills CSS animations mid-transition
- Resets scroll position inside scrollable elements
- Breaks third-party widgets that store state in the DOM

**Morphdom** solves this by comparing the old and new HTML and only
updating the specific elements that actually changed.

## Concepts You'll Learn

### innerHTML vs DOM Diffing

**innerHTML** (before):
```javascript
container.innerHTML = "<div><input value='hello'><p>Count: 5</p></div>";
// → Browser destroys ALL child elements
// → Rebuilds everything from scratch
// → Input loses focus, user's cursor position gone
```

**morphdom** (after):
```javascript
morphdom(container, newHtml);
// → Compares old DOM tree with new HTML
// → Only updates <p>Count: 5</p> → <p>Count: 6</p>
// → Input stays untouched — focus preserved!
```

### How Morphdom Works

Morphdom walks both trees (old DOM and new HTML) simultaneously:

1. **Same element, same attributes** → skip (no change needed)
2. **Same element, different attributes** → update only the attributes
3. **Same element, different text** → update only the text content
4. **New element** → insert it
5. **Missing element** → remove it

This is much faster than recreating everything, especially for large pages.

### onBeforeElUpdated Hook

Morphdom lets you intercept updates with hooks:

```javascript
morphdom(container, newHtml, {
  onBeforeElUpdated: function(fromEl, toEl) {
    // Preserve value of focused inputs
    if (fromEl === document.activeElement && fromEl.tagName === "INPUT") {
      toEl.value = fromEl.value;
    }
    return true;  // true = proceed with update
  }
});
```

This prevents the input's value from being overwritten when the user
is actively typing.

### Graceful Fallback

If morphdom fails to load, `ignite.js` falls back to `innerHTML`:

```javascript
function applyUpdate(container, newHtml) {
  if (typeof morphdom === "function") {
    // Use morphdom for efficient patching
    morphdom(container, wrapper);
  } else {
    // Fallback: replace everything
    container.innerHTML = newHtml;
  }
}
```

## The Code

### `assets/morphdom.min.js` (New)

**Create `assets/morphdom.min.js`:**

The morphdom library (~12KB minified). Loaded via a `<script>` tag
before `ignite.js` so it's available as a global function.

### Updated `assets/ignite.js`

**Replace `assets/ignite.js` with:**

New `applyUpdate()` function replaces the old `innerHTML` assignment:

```javascript
function applyUpdate(container, newHtml) {
  if (typeof morphdom === "function") {
    var wrapper = document.createElement("div");
    wrapper.id = APP_CONTAINER_ID;
    wrapper.innerHTML = newHtml;
    morphdom(container, wrapper, {
      onBeforeElUpdated: function(fromEl, toEl) {
        if (fromEl === document.activeElement && fromEl.tagName === "INPUT") {
          toEl.value = fromEl.value;
        }
        return true;
      }
    });
  } else {
    container.innerHTML = newHtml;
  }
}
```

### Updated `templates/live.html.eex`

**Replace `templates/live.html.eex` with:**

Loads morphdom before ignite.js:
```html
<script src="/assets/morphdom.min.js"></script>
<script src="/assets/ignite.js"></script>
```

## How It Works

```
1. Server sends update: {d: ["<h1>Count: 6</h1>..."]}

2. JS reconstructs full HTML from statics + dynamics

3. Instead of:
   container.innerHTML = newHtml  (destroys everything)

4. We do:
   morphdom(container, newHtml)  (patches only changes)

5. Morphdom compares:
   Old: <p>5</p>  →  New: <p>6</p>
   Only the text node "5" → "6" is updated.
   Everything else stays untouched.
```

## Try It Out

1. Start the server: `iex -S mix`

2. Visit http://localhost:4000/counter

3. Open the browser console. You should see:
   ```
   [Ignite] LiveView connected (morphdom: true)
   ```

4. Click the buttons — counter still works.

5. Open DevTools → Elements tab. Watch the DOM as you click:
   - With morphdom: only the count text node flashes (gets updated)
   - Without morphdom: the entire `#ignite-app` div would flash

6. The real benefit shows when you have inputs. If you add a text
   input to your LiveView template, typing in it won't be interrupted
   by server updates.

## File Checklist

| File | Status |
|------|--------|
| `assets/morphdom.min.js` | **New** |
| `assets/ignite.js` | **Modified** |
| `templates/live.html.eex` | **Modified** |

## The Framework Is Complete!

Congratulations! You've built **Ignite** — a real web framework with:

| Layer | Component | Step |
|-------|-----------|------|
| Networking | TCP Socket → Cowboy | 1, 10 |
| Parsing | HTTP Parser | 2, 9 |
| Routing | Macro-based DSL | 3, 5 |
| Controllers | Response helpers | 4 |
| Reliability | OTP Supervision | 6 |
| Templates | EEx Engine | 7 |
| Middleware | Plug pipeline | 8 |
| Error Handling | try/rescue boundary | 11 |
| Real-time | LiveView + WebSocket | 12, 13 |
| Optimization | Diffing Engine | 14 |
| Dev Tools | Hot Code Reloader | 15 |
| UI Performance | Morphdom DOM diffing | 16 |

You understand the internals of Phoenix better than most developers
who just run `mix phx.new`. Every concept here — the conn pipeline,
macros, OTP supervision, LiveView — is the same architecture that
powers production Elixir applications.
