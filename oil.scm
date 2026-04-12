(require "helix/editor.scm")
(require "helix/misc.scm")
(require "helix/static.scm")
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

(define (entry-display-name full-path)
  (let ([name (basename full-path)])
    (if (is-file? full-path)
        name
        (string-append name "/"))))

(define (read-oil-entries dir)
    (let* ([raw     (with-handler
                      (lambda (err)
                        (error (string-append "Cannot read directory: "
                                              (error-object-message err))))
                      (read-dir dir))]
           ; convert a full path into a simple path like "folder-name/"
           [entries (map entry-display-name raw)]
           ; filter entries by ending in "/"
           [dirs    (sort (filter (lambda (e) (ends-with? e "/")) entries) string<?)]
           [files   (sort (filter (lambda (e) (not (ends-with? e "/"))) entries) string<?)])
      (append (list "../") dirs files)))


(define (oil)
    ; pritn text in the statusline
    (let* ([doc-id  (editor->doc-id (editor-focus))]
           [path    (editor-document->path doc-id)]
           [dir     (if path (parent-name path) (get-helix-cwd))]
           [entries (read-oil-entries (normalize-dir dir))])
      (set-status! (string-join entries "  "))))
