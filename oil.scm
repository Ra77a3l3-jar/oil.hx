(require "helix/editor.scm")
(require "helix/misc.scm")
(require "helix/static.scm")
(require "helix/ext.scm")
(require "helix/keymaps.scm")
(require-builtin helix/core/text as text.)
(require (prefix-in helix. "helix/commands.scm"))

; creates the cmd :oil
(provide oil oil-enter oil-up oil-refresh)

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

(define (entries-are-dir? name)
    (ends-with? name "/"))

(define (full-path-for entry)
    (if (entries-are-dir? entry)
        (path-join *oil-dir* (trim-end-matches entry "/"))
        (path-join *oil-dir* entry)))

 (define (do-rename! old-name new-name)
    (let* ([old-path (full-path-for old-name)]
           [new-path (full-path-for new-name)]
           ; ~> pipes the value to the process mv and spawns the process
           [proc     (~> (command "mv" (list old-path new-path))
                         with-stdout-piped
                         with-stderr-piped
                         spawn-process)])
      (if (Ok? proc)
          (let ([stderr (read-port-to-string (child-stderr (Ok->value proc)))])
            (when (not (string=? (trim stderr) ""))
              (error (trim stderr))))
          (error "mv: could not spawn process"))))

(define (do-delete! name)
    (let ([path (full-path-for name)])
      (if (entries-are-dir? name)
          (delete-directory! path) ; only works if empty
          (delete-file! path))))

(define (do-create! name)
    (let ([path (full-path-for name)])
      (if (entries-are-dir? name)
          (create-directory! path)
          ; call-with-output-file allows to create a file without opening
          (call-with-output-file path (lambda (_p) (void))))))

; check at each change if it can be a rename or a change like new file or delete
(define (pair-renames removed added)
    (let loop ([rem removed] [add added] [renames '()] [leftover-rem '()] [leftover-add '()])
      (cond
        [(and (null? rem) (null? add))
         (list (reverse renames) (reverse leftover-rem) (reverse leftover-add))]

        [(null? rem)
         (list (reverse renames) (reverse leftover-rem) (append (reverse leftover-add) add))]

        [(null? add)
         (list (reverse renames) (append (reverse leftover-rem) rem) (reverse leftover-add))]

        ;d Same type (file/file or dir/dir) → rename pair
        [(equal? (entries-are-dir? (car rem))
                 (entries-are-dir? (car add)))
         (loop (cdr rem) (cdr add)
               (cons (cons (car rem) (car add)) renames)
               leftover-rem
               leftover-add)]

        ; different types → can't pair, carry both forward
        [else
         (loop (cdr rem) (cdr add)
               renames
               (cons (car rem) leftover-rem)
               (cons (car add) leftover-add))])))

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
    (let* ([doc-id (editor->doc-id (editor-focus))]
           [path   (editor-document->path doc-id)]
           [dir    (if path (parent-name path) (get-helix-cwd))])
      (open-oil-for-dir dir)))

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
