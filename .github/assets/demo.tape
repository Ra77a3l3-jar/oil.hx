# VHS tape for oil.hx — https://github.com/charmbracelet/vhs
# Run with: vhs demo.tape
#
# Uses ~/Dev/ziglings as the sandbox project: it's a git repo, so any mistake
# is trivially reversible, and every throwaway file this script creates gets
# deleted again by the end, so the repo is left exactly as it was found.
#
# oil.hx edits a real Helix buffer as a directory listing — create/rename/
# delete are done with normal Helix editing (add a line, edit text, select +
# delete a line), then :oil-save applies the diff to disk.
#
# Keybinds are read from ~/.config/helix/init.scm: (space (o (o ":oil")
# (e ":oil-enter") (u ":oil-up") (g ":oil-root") (s ":oil-save")
# (h ":oil-toggle-hidden") (d ":oil-toggle-metadata") (q ":oil-close")
# (m (y ":oil-yank") (x ":oil-cut") (p ":oil-paste") (c ":oil-clipboard-clear")))).

Require hx

Output "/home/raffaele/Dev/plugins/demos/oil-demo-catpp.gif"

Set Shell "bash"
Set Theme "VibrantInk"
Set FontFamily "JetBrainsMono Nerd Font Mono"
Set FontSize 18
Set Width 1600
Set Height 1000
Set Padding 20
Set TypingSpeed 60ms
Set WindowBar Colorful

Hide
Type "cd ~/Dev/ziglings && hx README.md"
Enter
Sleep 1.5s
Type ":theme catppuccin_mocha_transparent"
Enter
Sleep 1s
Show

Sleep 500ms

# open oil at the workspace root (README.md's directory)
Space
Type@80ms "oo"
Sleep 1s

# navigate to images/ (2 down from ../) and enter it
Down@250ms 2
Sleep 400ms
Space
Type@80ms "oe"
Sleep 800ms

Down@300ms 1
Sleep 400ms

# jump straight back to the repo root, regardless of depth
Space
Type@80ms "og"
Sleep 800ms

# toggle hidden dotfiles on, then off again
Space
Type@80ms "oh"
Sleep 900ms
Space
Type@80ms "oh"
Sleep 500ms

# navigate to test/ (4 down from ../) and enter it — a small, safe directory
Down@250ms 4
Sleep 400ms
Space
Type@80ms "oe"
Sleep 800ms

# create a file: jump to the last line, open a new line below, type a name
Type@80ms "ge"
Sleep 400ms
Type "o"
Sleep 300ms
Type@80ms "demo-note.txt"
Sleep 300ms
Escape
Sleep 300ms
Space
Type@80ms "os"
Sleep 1.2s

# rename in place: go to line start, insert mode, delete the old prefix, retype
Down@250ms 1
Sleep 400ms
Type@80ms "gh"
Sleep 300ms
Type "i"
Sleep 300ms
Delete@60ms 9
Sleep 300ms
Type@80ms "renamed-note"
Sleep 300ms
Escape
Sleep 300ms
Space
Type@80ms "os"
Sleep 1.2s

# delete: select the whole line, delete it, save
Down@250ms 1
Sleep 400ms
Type "x"
Sleep 300ms
Type "d"
Sleep 300ms
Space
Type@80ms "os"
Sleep 1.2s

# --- copy and move, via the clipboard sub-menu (space o m ...) ---

# create a second file here to copy/move around
Type@80ms "ge"
Sleep 400ms
Type "o"
Sleep 300ms
Type@80ms "copy-note.txt"
Sleep 300ms
Escape
Sleep 300ms
Space
Type@80ms "os"
Sleep 1.2s

# yank it, demonstrate clearing the clipboard, then yank again for real
Down@250ms 1
Sleep 400ms
Space
Type@80ms "omy"
Sleep 800ms
Space
Type@80ms "omc"
Sleep 700ms
Space
Type@80ms "omy"
Sleep 800ms

# jump to the root and paste — creates a copy alongside the original
Space
Type@80ms "og"
Sleep 1.2s
Space
Type@80ms "omp"
Sleep 1.5s

# cut that root copy (11 down from ../, since it sorts last among files)
# and move it into images/. Every navigation here counts Down from a
# freshly-reset ../ rather than counting Up from wherever a prior action
# left the cursor — the only proven-reliable pattern in this tape.
Down@150ms 11
Sleep 500ms
Space
Type@80ms "omx"
Sleep 1s
Space
Type@80ms "og"
Sleep 1.2s
Down@250ms 2
Sleep 400ms
Space
Type@80ms "oe"
Sleep 1.2s
Space
Type@80ms "omp"
Sleep 1.5s

# clean up: delete the moved copy from images/
Down@250ms 1
Sleep 400ms
Type "x"
Sleep 300ms
Type "d"
Sleep 300ms
Space
Type@80ms "os"
Sleep 1.2s

# ...and the original copy back in test/
Space
Type@80ms "og"
Sleep 1.2s
Down@250ms 4
Sleep 400ms
Space
Type@80ms "oe"
Sleep 1.2s
Down@250ms 1
Sleep 400ms
Type "x"
Sleep 300ms
Type "d"
Sleep 300ms
Space
Type@80ms "os"
Sleep 1.2s

# toggle file metadata (permissions/size) inlay hints on, then off
Space
Type@80ms "od"
Sleep 900ms
Space
Type@80ms "od"
Sleep 500ms

# close the oil buffer
Space
Type@80ms "oq"
Sleep 500ms

Hide
Type ":q!"
Enter
Sleep 500ms
