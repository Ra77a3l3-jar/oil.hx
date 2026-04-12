(require "helix/editor.scm")
(require "helix/misc.scm")
(require (prefix-in helix. "helix/commands.scm"))

; creates the cmd :oil
(provide oil)

(define (path-join base name)
  (string-append base (path-separator) name))

(define (basename full-path)
  (let* ([parts (split-many full-path (path-separator))]
         ; let* parts  can be referenced and split-many does the parsig
         [nonempty (filter (lambda (s) (> (string-length s) 0)) parts)])
         ; filter out empty string
    (if (null? nonempty)
        full-path
        (list-ref nonempty (- (length nonempty) 1)))))

(define (normalize-dir dir)
  (with-handler
    (lambda (_) dir)
    ; returns the input dir if canonilazation fails
    (let ([canonical (canonicalize-path dir)])
      ; canonicalize-path resolves paths to absolute path
      (if (and (> (string-length canonical) 1)
               (ends-with? canonical (path-separator)))
               ; remove / if more than 1 arg
          (trim-end-matches canonical (path-separator))
          canonical))))

(define (oil)  
  ; pritn text in the statusline
  (set-status! (basename (editor-document->path
                              (editor->doc-id (editor-focus))))))
