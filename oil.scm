(require "helix/editor.scm")
(require "helix/misc.scm")
(require "helix/static.scm")
(require "helix/ext.scm")
(require-builtin helix/core/text as text.)
(require (prefix-in helix. "helix/commands.scm"))

; creates the cmd :oil
(provide oil
         oil-enter
         oil-up
         oil-root
         oil-refresh
         oil-save
         oil-close
         oil-toggle-hidden
         oil-toggle-git-ignored
         oil-toggle-metadata
         oil-configure!
         oil-yank
         oil-cut
         oil-paste
         oil-clipboard-clear)

(define OIL-BUFFER-NAME "*oil*")

(define *oil-dir* #false)
(define *oil-doc-id* #false)
(define *oil-original* '())
(define *oil-git-status* '())
(define *oil-hint-ids* '())
(define *oil-clipboard-op* #false)
(define *oil-clipboard-path* #false)
(define *oil-show-hidden* #false)
(define *oil-show-git-ignored* #false)
(define *oil-metadata* '())
(define *oil-show-metadata* #false)

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

(define (hidden-entry? name)
  (and (> (string-length name) 0)
       (char=? (string-ref name 0) #\.)))

(define (read-oil-entries dir)
    (let* ([raw     (with-handler
                      (lambda (err)
                        (error (string-append "Cannot read directory: "
                                              (error-object-message err))))
                      (read-dir dir))]
           [entries (map entry-display-name raw)]
           [visible (if *oil-show-hidden*
                        entries
                        (filter (lambda (e)
                                  (not (hidden-entry? (trim-end-matches e "/"))))
                                entries))]
           [dirs    (sort (filter (lambda (e) (ends-with? e "/")) visible) string<?)]
           [files   (sort (filter (lambda (e) (not (ends-with? e "/"))) visible) string<?)])
      (append (list "../") dirs files)))

(define (format-file-size bytes-str)
  (let ([n (string->number bytes-str)])
    (cond
      [(not n) "?"]
      [(< n 1024) (string-append (number->string n) "B")]
      [(< n (* 1024 1024)) (string-append (number->string (quotient n 1024)) "K")]
      [(< n (* 1024 1024 1024)) (string-append (number->string (quotient n (* 1024 1024))) "M")]
      [else (string-append (number->string (quotient n (* 1024 1024 1024))) "G")])))

(define (format-permissions perms)
  ; strip leading '-' for regular files (uninformative), keep 'd', 'l', etc.
  (if (and (> (string-length perms) 1)
           (char=? (string-ref perms 0) #\-))
      (substring perms 1 (string-length perms))
      perms))

(define (pad-left s width)
  (let ([n (string-length s)])
    (if (>= n width) s
        (string-append (make-string (- width n) #\space) s))))

(define (pad-right s width)
  (let ([n (string-length s)])
    (if (>= n width) s
        (string-append s (make-string (- width n) #\space)))))

(define (list-max-length strs)
  (let loop ([lst strs] [m 0])
    (if (null? lst) m
        (loop (cdr lst) (max m (string-length (car lst)))))))

(define (read-entry-metadata! dir entries)
  (let* ([names (filter (lambda (e) (not (string=? e "../"))) entries)]
         [paths (map (lambda (e) (path-join dir (trim-end-matches e "/"))) names)])
    (if (null? paths)
        (set! *oil-metadata* '())
        (let ([proc (~> (command "stat" (cons "--printf=%n\t%A\t%h\t%s\n" paths))
                        with-stdout-piped with-stderr-piped spawn-process)])
          (if (Ok? proc)
              (let* ([output (read-port-to-string (child-stdout (Ok->value proc)))]
                     [lines (filter (lambda (l) (> (string-length l) 0))
                                     (split-many output "\n"))])
                (set! *oil-metadata*
                      (filter (lambda (x) x)
                              (map (lambda (line)
                                     (let ([parts (split-many line "\t")])
                                       (if (>= (length parts) 4)
                                           (cons (basename (list-ref parts 0))
                                                 (list (list-ref parts 1)
                                                       (list-ref parts 2)
                                                       (list-ref parts 3)))
                                           #false)))
                                   lines))))
              (set! *oil-metadata* '()))))))

(define (make-buffer-text dir entries)
    (let* ([flags  (string-append
                     ; display if the git ignored toggle or the dotfile toggle is active
                     (if *oil-show-hidden* " [+h]" "")
                     (if *oil-show-git-ignored* " [+i]" ""))]
           [header (string-append dir flags "\n")]
           [body   (string-join entries "\n")])
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
            (collapse_selection) ; prevents selection
            (helix.goto-line 2))
          (begin
            (insert_string content)
            (helix.goto-line 2)))))

(define (entries-are-dir? name)
    (ends-with? name "/"))

(define (full-path-for entry)
    (if (entries-are-dir? entry)
        (path-join *oil-dir* (trim-end-matches entry "/"))
        (path-join *oil-dir* entry)))

(define (run-mv! from-path to-path)
  (let ([proc (~> (command "mv" (list from-path to-path))
                  with-stdout-piped
                  with-stderr-piped
                  spawn-process)])
    (if (Ok? proc)
          (let ([stderr (read-port-to-string (child-stderr (Ok->value proc)))])
            (when (not (string=? (trim stderr) ""))
              (error (trim stderr))))
          (error "mv: could not spawn process"))))

(define (run-mkdir-p! path)
    (let ([proc (~> (command "mkdir" (list "-p" path)) ; allows to create nested folders with parent new
                    with-stdout-piped
                    with-stderr-piped
                    spawn-process)])
      (if (Ok? proc)
          (let ([stderr (read-port-to-string (child-stderr (Ok->value proc)))])
            (when (not (string=? (trim stderr) ""))
              (error (trim stderr))))
          (error "mkdir: could not spawn process"))))

(define (run-cp-r! src dest)
    ; -r copies directories recursively and works for files
    (let ([proc (~> (command "cp" (list "-r" src dest))
                    with-stdout-piped
                    with-stderr-piped
                    spawn-process)])
      (if (Ok? proc)
          (let ([stderr (read-port-to-string (child-stderr (Ok->value proc)))])
            (when (not (string=? (trim stderr) ""))
              (error (trim stderr))))
          (error "cp: could not spawn process"))))

(define (oil-current-entry)
    (and (oil-buffer-alive?)
         (let* ([rope   (editor->text *oil-doc-id*)]
                [text   (text.rope->string rope)]
                [lines  (split-many text "\n")]
                [line-n (get-current-line-number)]
                [entry  (if (< line-n (length lines))
                            (trim (list-ref lines line-n))
                            #false)])
           (and entry
                (not (string=? entry ""))
                (not (starts-with? entry *oil-dir*))
                (not (string=? entry "../"))
                entry))))

(define (do-delete! name)
    (let ([path (full-path-for name)])
      (if (entries-are-dir? name)
          (delete-directory! path) ; only works if empty
          (delete-file! path))))

(define (do-create! name)
    (let ([path (full-path-for name)])
      (if (entries-are-dir? name)
          (run-mkdir-p! path)
          (begin
            (run-mkdir-p! (parent-name path))   ; ensure parent exists first
            ; call-with-output-file allows to create a file without opening
            (call-with-output-file path (lambda (_p) (void)))))))

(define (pair-same-type removed added)
    ; pairs entries of the same type in order
    (let loop ([rem removed] [add added] [renames '()] [leftover-rem '()] [leftover-add '()])
      (cond
        [(and (null? rem) (null? add))
         (list (reverse renames) (reverse leftover-rem) (reverse leftover-add))]
        [(null? rem)
         (list (reverse renames) (reverse leftover-rem) (append (reverse leftover-add) add))]
        [(null? add)
         (list (reverse renames) (append (reverse leftover-rem) rem) (reverse leftover-add))]
        [else
         (loop (cdr rem) (cdr add)
               (cons (cons (car rem) (car add)) renames)
               leftover-rem
               leftover-add)])))

; check at each change if it can be a rename or a change like new file or delete
(define (pair-renames removed added)
    ; it splits by type and pairs each group independently then merge result
    (let* ([is-file?   (lambda (e) (not (entries-are-dir? e)))]
           [rem-dirs   (filter entries-are-dir? removed)]
           [rem-files  (filter is-file? removed)]
           [add-dirs   (filter entries-are-dir? added)]
           [add-files  (filter is-file? added)]
           [dir-result  (pair-same-type rem-dirs  add-dirs)]
           [file-result (pair-same-type rem-files add-files)])
      (list (append (list-ref dir-result 0) (list-ref file-result 0))
            (append (list-ref dir-result 1) (list-ref file-result 1))
            (append (list-ref dir-result 2) (list-ref file-result 2)))))

(define (open-oil-for-dir dir)
    (let* ([canonical (normalize-dir dir)]
           [git-status (if (git-repo? canonical)
                            (parse-git-status-pairs canonical)
                            '())]
           [raw-entries (with-handler
                          (lambda (err)
                            (set-error! (string-append "oil: " (error-object-message err)))
                            '())
                          (read-oil-entries canonical))]
           [entries (if *oil-show-git-ignored*
                            raw-entries
                            (filter (lambda (e)
                                      (not (git-ignored-in? e git-status)))
                                    raw-entries))])
      (set! *oil-dir* canonical)
      (set! *oil-original* entries)
      (set! *oil-git-status* git-status)
      (when *oil-show-metadata*
        (read-entry-metadata! canonical entries))

      (if (oil-buffer-alive?)
          (begin
            (editor-switch-action! *oil-doc-id* (Action/Replace))
            (populate-oil-buffer! canonical entries)
            (enqueue-thread-local-callback
                (lambda ()
                  (clear-oil-hints!)
                  (apply-oil-hints! entries))))
          (begin
            (helix.new)
            (enqueue-thread-local-callback
              (lambda ()
                (let* ([view-id (editor-focus)]
                       [doc-id  (editor->doc-id view-id)])
                  (set! *oil-doc-id* doc-id)
                  (set-scratch-buffer-name! OIL-BUFFER-NAME)
                  (populate-oil-buffer! canonical entries)
                  (clear-oil-hints!)
                  (apply-oil-hints! entries))))))))

(define (git-repo? dir)
  (let ([proc (~> (command "git" (list "-C" dir "rev-parse" "--is-inside-work-tree"))
                  with-stdout-piped
                  with-stderr-piped
                  spawn-process)])
    (and (Ok? proc)
         ; extracts from Ok and gets the stdout to check if there is the "true" returned by git
         (string=? (trim (read-port-to-string (child-stdout (Ok->value proc)))) "true"))))

(define (git-repo-root dir)
    (let ([proc (~> (command "git" (list "-C" dir "rev-parse" "--show-toplevel"))
                    with-stdout-piped with-stderr-piped spawn-process)])
      (if (Ok? proc)
          ; extracts from Ok and gets the stdout to check if there is the "true" returned by git
          (let ([out (trim (read-port-to-string (child-stdout (Ok->value proc))))])
            (if (string=? out "") #false out))
          #false)))

(define (parse-git-line line)
    ; parse one porcelain line, returns alist or #false to skip.
    (if (< (string-length line) 4)
        #false
        ; extracting status chars from porcellain
        (let* ([x    (substring line 0 1)]
               [y    (substring line 1 2)]
               [path (trim (substring line 3 (string-length line)))]
               ; renames look like "old.txt -> new.txt" — we only care about the new name
               [path (if (string=? x "R")
                         (let ([parts (split-many path " -> ")])
                           (if (>= (length parts) 2) (list-ref parts 1) path))
                         path)]
               [label (cond
                        [(string=? x "?") " ?"]   ; untracked
                        [(string=? x "!") " !"]   ; ignored
                        [(string=? x "R") " →"]   ; renamed
                        [(string=? x "A") " +"]   ; new staged file
                        [(or (string=? x "M")
                             (string=? y "M")) " ~"]  ; modified
                        [else #false])])
          (if label (cons label path) #false))))

(define (git-ignored-in? entry git-status)
  (let ([name (if (entries-are-dir? entry)
                  (trim-end-matches entry "/")
                  entry)])
    (let loop ([ps git-status])
      (if (null? ps)
          #false
          (if (and (string=? (car (car ps)) " !")
                   (or (string=? (cdr (car ps)) name)
                       (starts-with? (cdr (car ps)) (string-append name "/"))))
              #true
              (loop (cdr ps)))))))

(define (parse-git-status-pairs dir)
    (let* ([root (git-repo-root dir)]
           [proc (~> (command "git" (list "-C" dir "status" "--porcelain" "--ignored"))
                     with-stdout-piped with-stderr-piped spawn-process)])
      (if (Ok? proc)
          (let* ([output (read-port-to-string (child-stdout (Ok->value proc)))]
                 [lines  (filter (lambda (l) (> (string-length l) 0))
                                 (split-many output "\n"))]
                 [prefix (if (or (not root) (string=? dir root))
                             ""
                             (string-append (substring dir (+ (string-length root) 1)) "/"))])
            (filter (lambda (x) x)
                    (map (lambda (line)
                           (let ([pair (parse-git-line line)])
                             (and pair
                                  (let* ([label    (car pair)]
                                         [git-path (cdr pair)]
                                         [rel      (if (string=? prefix "")
                                                       git-path
                                                       (if (starts-with? git-path prefix)
                                                           (substring git-path (string-length prefix))
                                                           #false))])
                                    (and rel (cons label rel))))))
                         lines)))
          '())))

(define (entry-git-status entry)
  (let ([name (if (entries-are-dir? entry)
                  (trim-end-matches entry "/") ; trim / from dir
                  entry)])
    (let loop ([ps *oil-git-status*]) ; loops alist
      (if (null? ps)
          #false
          (let ([git-path (cdr (car ps))]
                [lable (car (car ps))])
            ; match file or directory
            (if (or (string=? git-path name)
                    (starts-with? git-path (string-append name "/")))
                lable
                (loop (cdr ps))))))))

(define (entry-metadata-hint entry)
  (let* ([name (trim-end-matches entry "/")]
         [meta (assoc name *oil-metadata*)])
    (and meta
         (let* ([vals (cdr meta)]
                [perms (list-ref vals 0)]
                [links (list-ref vals 1)]
                [size (list-ref vals 2)])
           ; fixed-width columns: perms=10 links=3 size=5
           (string-append (pad-right (format-permissions perms) 10)
                          "  " (pad-left links 3)
                          "  " (pad-left (format-file-size size) 5))))))

(define (build-entry-hint entry)
  (let ([git (entry-git-status entry)]
        [meta (and *oil-show-metadata* (entry-metadata-hint entry))])
    (cond
      [(and git meta) (string-append meta "  " git)]
      [git git]
      [meta meta]
      [else #false])))

(define (line-end-char-index lines n)
    (let loop ([i 0] [pos 0])
      (if (= i n)
          (+ pos (string-length (list-ref lines i)))
          (loop (+ i 1) (+ pos (string-length (list-ref lines i)) 1)))))

(define (clear-oil-hints!)
  (for-each
    (lambda (id) (remove-inlay-hint-by-id (list-ref id 0) (list-ref id 1)))
    *oil-hint-ids*)
  (set! *oil-hint-ids* '()))

(define (apply-oil-hints! entries)
  ; entries[0] = "../" lives on buffer line 1 and line 0 is the header
  (when (oil-buffer-alive?)
    (let* ([rope (editor->text *oil-doc-id*)]
           [text (text.rope->string rope)]
           [lines (split-many text "\n")]
           [max-len (list-max-length (if (> (length lines) 1) (cdr lines) '()))])
      (let loop ([i 0] [ents entries])
        (unless (null? ents)
          (let* ([entry (car ents)]
                 [line-n (+ i 1)]
                 [hint (build-entry-hint entry)])
            (when (and hint (< line-n (length lines)))
              (let* ([line-len (string-length (list-ref lines line-n))]
                     [pad (make-string (max 0 (+ (- max-len line-len) 2)) #\space)]
                     [hint-id (add-inlay-hint (line-end-char-index lines line-n)
                                               (string-append pad hint))])
                (set! *oil-hint-ids* (cons hint-id *oil-hint-ids*)))))
          (loop (+ i 1) (cdr ents)))))))

(define (reapply-oil-hints!)
    (when (oil-buffer-alive?)
      (clear-oil-hints!)
      (let* ([rope (editor->text *oil-doc-id*)]
             [text (text.rope->string rope)]
             [lines (split-many text "\n")]
             [max-len (list-max-length (if (> (length lines) 1) (cdr lines) '()))])
        (let loop ([i 1])   ; i=0 is the header line, skip it
          (when (< i (length lines))
            (let* ([entry (trim (list-ref lines i))]
                   [hint (if (> (string-length entry) 0)
                                 (build-entry-hint entry)
                                 #false)])
              (when hint
                (let* ([line-len (string-length (list-ref lines i))]
                       [pad (make-string (max 0 (+ (- max-len line-len) 2)) #\space)]
                       [id (add-inlay-hint (line-end-char-index lines i)
                                                 (string-append pad hint))])
                  (set! *oil-hint-ids* (cons id *oil-hint-ids*)))))
            (loop (+ i 1)))))))

;;@doc
;; Open oil file manager
(define (oil)
    (let* ([doc-id (editor->doc-id (editor-focus))]
           [path   (editor-document->path doc-id)]
           [dir    (if path (parent-name path) (get-helix-cwd))])
      (open-oil-for-dir dir)))

;;@doc
;; Enter directory or open file
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

;;@doc
;; Go to parent directory
(define (oil-up)
  (if *oil-dir*
      (open-oil-for-dir (parent-name *oil-dir*))
      (set-error! "no active oil buffer")))

;;@doc
;; Refresh oil buffer
(define (oil-refresh)
  (if *oil-dir*
      (open-oil-for-dir *oil-dir*)
      (set-error! "no active oil buffer")))

;;@doc
;; Jump to the git repository root, or helix cwd if not in a repo
(define (oil-root)
  (let ([root (and *oil-dir* (git-repo-root *oil-dir*))])
    (open-oil-for-dir (or root (get-helix-cwd)))))

;;@doc
;; Toggle visibility of hidden (dot) files and directories
(define (oil-toggle-hidden)
  (if *oil-dir*
      (begin
        (set! *oil-show-hidden* (not *oil-show-hidden*))
        (open-oil-for-dir *oil-dir*)
        (set-status! (if *oil-show-hidden*
                         "oil: showing dotfiles"
                         "oil: hiding dotfiles")))
      (set-error! "no active oil buffer")))

;;@doc
;; Toggle visibility of git-ignored files and directories
(define (oil-toggle-git-ignored)
  (if *oil-dir*
      (begin
        (set! *oil-show-git-ignored* (not *oil-show-git-ignored*))
        (open-oil-for-dir *oil-dir*)
        (set-status! (if *oil-show-git-ignored*
                         "oil: showing git-ignored files"
                         "oil: hiding git-ignored files")))
      (set-error! "no active oil buffer")))

;;@doc
;; Set default visibility for dotfiles and git-ignored entries.
(define (oil-configure! show-hidden show-git-ignored)
  (set! *oil-show-hidden* show-hidden)
  (set! *oil-show-git-ignored* show-git-ignored))

;;@doc
;; Save oil changes
(define (oil-save)
    (unless (oil-buffer-alive?)
      (set-error! "no active oil buffer Run :oil first")
      (void))

    (when (oil-buffer-alive?)
      (let* ([rope    (editor->text *oil-doc-id*)]
             [current (parse-buffer-entries rope)]

             ; strip "../" from both sides before pairing
             [orig    (filter (lambda (e) (not (string=? e "../"))) *oil-original*)]
             [curr    (filter (lambda (e) (not (string=? e "../"))) current)]

             [removed (filter (lambda (e) (not (member e curr))) orig)]
             [added   (filter (lambda (e) (not (member e orig))) curr)]

             ; pair renames
             [result    (pair-renames removed added)]
             [renames   (list-ref result 0)]
             [to-delete (list-ref result 1)]
             [to-create (list-ref result 2)])

        ; collect errors without aborting
        (define errors '())

        (define (try! label thunk)
          (with-handler
            (lambda (err)
              (set! errors
                    (cons (string-append label ": " (error-object-message err))
                          errors)))
            (thunk)))

        ; renames file
        (let ([actual (filter (lambda (p) (not (string=? (car p) (cdr p)))) renames)])

            ; moves every source to a temp name
            (for-each
            (lambda (pair)
                (try! (string-append "rename " (car pair) " -> " (cdr pair))
                    (lambda ()
                        (run-mv! (full-path-for (car pair))
                                (string-append (full-path-for (car pair)) ".~oil~")))))
            actual)

            ; moves every temp name to the final destination
            (for-each
            (lambda (pair)
                (try! (string-append "rename " (car pair) " -> " (cdr pair))
                    (lambda ()
                        (run-mv! (string-append (full-path-for (car pair)) ".~oil~")
                                (full-path-for (cdr pair))))))
            actual))

        ; delete
        (for-each
          (lambda (name)
            (try! (string-append "delete " name)
                  (lambda () (do-delete! name))))
          to-delete)

        ; create a new file
        (for-each
          (lambda (name)
            (try! (string-append "create " name)
                  (lambda () (do-create! name))))
          to-create)

        ; report and refresh
        (if (null? errors)
            (begin
              (let ([n (+ (length renames) (length to-delete) (length to-create))])
                (if (= n 0)
                    (set-status! "nothing to do")
                    (set-status! (string-append "applied "
                                                (number->string n)
                                                " operation(s) in "
                                                *oil-dir*))))
              (open-oil-for-dir *oil-dir*))
            (begin
              (open-oil-for-dir *oil-dir*) ; refresh even on partial failure
              (set-error! (string-append "errors: "
                                         (string-join (reverse errors) " | "))))))))

;;@doc
;; Close the oil buffer
(define (oil-close)
    (helix.buffer-close!))

;;@doc
;; Mark the entry under cursor for copying
(define (oil-yank)
    (let ([entry (oil-current-entry)])
      (if entry
          (begin
            (set! *oil-clipboard-op*   'copy)
            (set! *oil-clipboard-path* (full-path-for entry))
            ; basename shows just the name not the full path
            (set-status! (string-append "yank: " entry)))
          (set-error! "no entry under cursor"))))

;;@doc
;; Mark the entry under cursor for moving
(define (oil-cut)
    (let ([entry (oil-current-entry)])
      (if entry
          (begin
            (set! *oil-clipboard-op*   'move)
            (set! *oil-clipboard-path* (full-path-for entry))
            (set-status! (string-append "cut: " entry)))
          (set-error! "no entry under cursor"))))

;;@doc
;; Paste clipboard item into the current oil directory
(define (oil-paste)
    (cond
      [(not (oil-buffer-alive?))
       (set-error! "no active oil buffer")]

      [(not *oil-clipboard-path*)
       (set-error! "clipboard is empty")]

      [else
       (let* ([src  *oil-clipboard-path*]
              [name (basename src)]
              [dest (path-join *oil-dir* name)])
         (with-handler
           (lambda (err)
             (set-error! (string-append "paste failed: " (error-object-message err))))
           (begin
             (cond
               [(eq? *oil-clipboard-op* 'copy)
                (run-cp-r! src dest)
                (set-status! (string-append "copied " name " -> " *oil-dir*))]
               [(eq? *oil-clipboard-op* 'move)
                (run-mv! src dest)
                (set! *oil-clipboard-op*   #false)
                (set! *oil-clipboard-path* #false)
                (set-status! (string-append "moved " name " -> " *oil-dir*))])
             (open-oil-for-dir *oil-dir*))))]))


;;@doc
;; Clear the clipboard
(define (oil-clipboard-clear)
    (set! *oil-clipboard-op*   #false)
    (set! *oil-clipboard-path* #false)
    (set-status! "clipboard cleared"))

;;@doc
;; Toggle display of file permissions, hard-link count, and size as inlay hints
(define (oil-toggle-metadata)
  (if (oil-buffer-alive?)
      (begin
        (set! *oil-show-metadata* (not *oil-show-metadata*))
        (when *oil-show-metadata*
          (read-entry-metadata! *oil-dir* *oil-original*))
        (enqueue-thread-local-callback reapply-oil-hints!)
        (set-status! (if *oil-show-metadata*
                         "oil: showing metadata"
                         "oil: hiding metadata")))
      (set-error! "no active oil buffer")))

(register-hook 'document-changed
    (lambda (doc-id _old-text)
      (when (and (oil-buffer-alive?)
                 (equal? doc-id *oil-doc-id*)
                 (not (null? *oil-git-status*)))
        (enqueue-thread-local-callback reapply-oil-hints!))))
