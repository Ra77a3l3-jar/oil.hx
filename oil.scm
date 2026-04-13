(require "helix/editor.scm")
(require "helix/misc.scm")
(require "helix/static.scm")
(require "helix/ext.scm")
(require "helix/keymaps.scm")
(require-builtin helix/core/text as text.)
(require (prefix-in helix. "helix/commands.scm"))

; creates the cmd :oil
(provide oil oil-enter oil-up)

(define OIL-BUFFER-NAME "*oil*")

(define *oil-dir*      #false)
(define *oil-doc-id*   #false)
(define *oil-original* '())

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

(define (make-buffer-text dir entries)
    (let ([header (string-append "  " dir "\n")]
          ; joins items in list with a separator and add a new line at the end with two space
          [body   (string-join (map (lambda (e) (string-append "  " e)) entries) "\n")])
      (string-append header body)))

(define (parse-buffer-entries rope)
    (let* ([text  (text.rope->string rope)]
           [lines (split-many text "\n")]
           [data  (if (null? lines) '() (cdr lines))])
      (filter (lambda (e) (> (string-length e) 0))
              (map trim data))))

(define (oil-buffer-alive?)
  (and *oil-doc-id* (editor-doc-exists? *oil-doc-id*)))

(define (populate-oil-buffer! dir entries)
    (let ([content (make-buffer-text dir entries)])
      (if (oil-buffer-alive?)
          (begin
            (select_all)
            (replace-selection-with content)
            (helix.goto 2))
          (begin
            (insert_string content)
            (helix.goto 2)))))

(define (open-oil-for-dir dir)
    (let* ([canonical (normalize-dir dir)]
           [entries   (with-handler
                        (lambda (err)
                          (set-error! (string-append "oil: " (error-object-message err)))
                          '())
                        (read-oil-entries canonical))])

      (set! *oil-dir*      canonical)
      (set! *oil-original* entries)

      ; install keybindings
      (install-oil-keybindings!)

      (if (oil-buffer-alive?)
          (begin
            (editor-switch-action! *oil-doc-id* (Action/Replace))
            (populate-oil-buffer! canonical entries))
          (begin
            (helix.new)
            (enqueue-thread-local-callback
              (lambda ()
                (let* ([view-id (editor-focus)]
                       [doc-id  (editor->doc-id view-id)])
                  (set! *oil-doc-id* doc-id)
                  (set-scratch-buffer-name! OIL-BUFFER-NAME)
                  (populate-oil-buffer! canonical entries))))))))

(define (install-oil-keybindings!)
    ; keybindings when in a oil buffer.
    (keymap (buffer OIL-BUFFER-NAME)
            (normal
              (ret  ":oil-enter")
              ("-"  ":oil-up")
              (g    (s ":oil-save"))
              (R    ":oil-refresh")
              (q    ":buffer-close"))))

(define (oil)
    (let* ([doc-id  (editor->doc-id (editor-focus))]
           [path    (editor-document->path doc-id)]
           [dir     (normalize-dir (if path (parent-name path) (get-helix-cwd)))]
           [entries (with-handler
                      (lambda (err)
                        (set-error! (string-append "oil: " (error-object-message err)))
                        '())
                      (read-oil-entries dir))])
      (set! *oil-dir*      dir)
      (set! *oil-original* entries)
      (if (oil-buffer-alive?)
          (begin
            ; if buffer alredy created reference to existing one when :oil
            (editor-switch-action! *oil-doc-id* (Action/Replace))
            (populate-oil-buffer! dir entries))
          (begin
            (helix.new) ; creates and focuses the new buffer
            (enqueue-thread-local-callback
              (lambda ()
                (let* ([view-id (editor-focus)]
                       [doc-id  (editor->doc-id view-id)])
                  (set! *oil-doc-id* doc-id)
                  (set-scratch-buffer-name! OIL-BUFFER-NAME)
                  (populate-oil-buffer! dir entries))))))))

(define (oil-enter)
    (unless (oil-buffer-alive?)
      (set-error! "no active oil buffer")
      (void))

    (when (oil-buffer-alive?)
      (let* ([rope   (editor->text *oil-doc-id*)]
             [text   (text.rope->string rope)]
             [lines  (split-many text "\n")]
             [line-n (get-current-line-number)]
             [entry  (if (< line-n (length lines))
                         (trim (list-ref lines line-n))
                         #false)])
        (cond
          ; header line do nothing
          [(or (not entry) (string=? entry "") (starts-with? entry *oil-dir*))
           (void)]

          ; enter parent directory
          [(string=? entry "../")
           (open-oil-for-dir (parent-name *oil-dir*))]

          ; enter folder
          [(ends-with? entry "/")
           (let ([dirname (trim-end-matches entry "/")])
             (open-oil-for-dir (path-join *oil-dir* dirname)))]

          ; open file in new buffer
          [else
           (helix.open (path-join *oil-dir* entry))]))))


; allows to navigate to parent directory shown in the buffer
(define (oil-up)
  (if *oil-dir*
      (open-oil-for-dir (parent-name *oil-dir*))
      (set-error! "no active oil buffer")))

(define (oil-refresh)
  (if *oil-dir*
      (open-oil-for-dir *oil-dir*)
      (set-error! "no active oil buffer")))
