# oil.hx

A file manager plugin for [Helix](https://github.com/helix-editor/helix/) that lets you edit your filesystem like a buffer
— create, rename, and delete files and directories without ever leaving the editor.
 
> Heavily inspired by [oil.nvim](https://github.com/stevearc/oil.nvim).

![oil.hx preview](assets/preview.gif)

---
 
## Installation
 
**1. Install the plugin-enabled fork of Helix** by following the instructions [here](https://github.com/mattwparas/helix/blob/steel-event-system/STEEL.md).
 
**2. Install oil.hx via forge:**
 
```sh
forge pkg install --git https://github.com/Ra77a3l3-jar/oil.hx.git
```
 
**3. Load the plugin** by adding this line to your `init.scm`:
 
```scheme
(require "oil/oil.scm")
```
 
---

## Usage
 
### Commands
 
| Command | Description |
|---|---|
| `:oil` | Open the file manager in the current directory |
| `:oil-enter` | Enter the directory under the cursor |
| `:oil-up` | Navigate to the parent directory |
| `:oil-save` | Apply all pending edits to the filesystem |
| `:oil-refresh` | Reload the buffer, discarding unsaved changes |
| `:oil-close` | Close the buffer |
| `:oil-yank` | Yank (copy) the entry under the cursor to the oil clipboard |
| `:oil-cut` | Cut the entry under the cursor to the oil clipboard |
| `:oil-paste` | Paste the oil clipboard entry into the current directory |
| `:oil-clipboard-clear` | Clear the oil clipboard |

### Keybindings (optional)
 
You can bind the commands to keys either in `config.toml` or in `init.scm`.
 
**`config.toml`:**
```toml
[keys.normal.space.o]
o = "oil"
e = "oil-enter"
u = "oil-up"
s = "oil-save"
r = "oil-refresh"
q = "oil-close"

[keys.normal.space.o.m]
y = "oil-yank"
x = "oil-cut"
p = "oil-paste"
c = "oil-clipboard-clear"
```
 
**`init.scm`:**
```scheme
(keymap (global)
  (normal
    (space
      (o
        (o ":oil")
        (e ":oil-enter")
        (u ":oil-up")
        (s ":oil-save")
        (r ":oil-refresh")
        (q ":oil-close")
        (m
          (y ":oil-yank")
          (x ":oil-cut")
          (p ":oil-paste")
          (c ":oil-clipboard-clear"))))))
```
 
With the above, all commands are reachable under `<space>o` and clipboard operations under `<space>om`

---

## Credits
 
The concept and workflow are directly inspired by [oil.nvim](https://github.com/stevearc/oil.nvim) by stevearc.
This is an adaptation of that idea for the Helix + Steel ecosystem.
