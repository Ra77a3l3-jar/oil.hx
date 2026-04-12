(require "helix/editor.scm")
(require "helix/misc.scm")
(require (prefix-in helix. "helix/commands.scm"))

; creates the cmd :oil
(provide oil)

(define (oil)
  ; pritn text in the statusline
  (set-status! "oil commad"))
