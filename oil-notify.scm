(require "oil/oil.scm")
(require "notify/notify.scm")

;; Optional notify.hx integration for oil.hx.
;; Require this file after "oil/oil.scm" in your init.scm to display oil messages
;; as notify.hx popups instead of status-line text.

(set-box! *oil-info-fn*
          (lambda (msg)
            (notify msg #:title "oil.hx")))

(set-box! *oil-error-fn*
          (lambda (msg)
            (notify msg #:severity 'error #:title "oil.hx")))
