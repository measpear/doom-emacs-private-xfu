;;; lang/org-private/autoload/org-babel.el -*- lexical-binding: t; -*-

;; * name
;;;###autoload
(defun +org-private/get-name-src-block ()
  (interactive)
  (let ((completion-ignore-case t)
        (case-fold-search t)
        (all-block-names (org-babel-src-block-names)))
    (ivy-read "Named Source Blocks: " all-block-names
              :require-match t
              :history 'get-name-src-block-history
              :preselect (let (select (thing-at-point 'symbol))
                           (if select (substring-no-properties select)))
              :caller '+org-private/get-name-src-block
              :action #'+org-private/get-name-src-block-action-insert)))

;;;###autoload
(defun +org-private/get-name-src-block-action-insert (x)
  (insert (concat "<<" x ">>\n")))

;; * ob-ipython
;;;###autoload
(defun *org-babel-ipython-initiate-session (&optional session params)
    "Create a session named SESSION according to PARAMS."
    (if (string= session "none")
        (error "ob-ipython currently only supports evaluation using a session.
Make sure your src block has a :session param.")
      (when (not (s-ends-with-p ".json" session))
        (ob-ipython--create-kernel (ob-ipython--normalize-session session)
                                   (cdr (assoc :kernel params))))
      (ob-ipython--create-repl (ob-ipython--normalize-session session) params)))

;;;###autoload
(defun *ob-ipython--create-repl (name &optional params)
    (let ((cmd (s-join " " (ob-ipython--kernel-repl-cmd name))))
      (if (string= "default" name)
          (progn
            (run-python cmd nil nil)
            (format "*%s*" python-shell-buffer-name))
        (if (string-match "^remote-.*ssh.json" name)
            (when (not (ignore-errors (process-live-p (get-process (format "Python:ob-ipython-%s" name)))))
              (let* ((remote (s-split "-" name))
                     (remote-host (nth 1 remote))
                     (remote-session (nth 3 remote)))
                (ob-ipython-generate-local-path-from-remote remote-session remote-host params)))
          (let* ((process-name (format "Python:ob-ipython-%s" name))
                 (buf (python-shell-make-comint cmd process-name t))
                 (proc (get-buffer-process process-name))
                 (dir (cdr (assoc :pydir params))))
            (if dir (with-current-buffer buf
                      (setq-local default-directory dir)))
            (sleep-for 1)
            (format "*%s*" process-name))))))

;;;###autoload
(defun *org-babel-execute:ipython (body params)
    "Execute a block of IPython code with Babel.
This function is called by `org-babel-execute-src-block'."
    (message default-directory)
    (let ((session (cdr (assoc :session params))))
      (org-babel-ipython-initiate-session session params))
    (ob-ipython--clear-output-buffer)
    (if (cdr (assoc :async params))
        (ob-ipython--execute-async body params)
      (ob-ipython--execute-sync body params)))

;;;###autoload
(defun *org-babel-edit-prep:ipython (info)
  (let* ((params (nth 2 info))
         (session (cdr (assoc :session params))))
    (org-babel-ipython-initiate-session session params))
  ;; Support for python.el's "send-code" commands within edit buffers.
  (setq-local python-shell-buffer-name
              (format "Python:ob-ipython-%s" (->> info (nth 2) (assoc :session) cdr
                                                  ob-ipython--normalize-session)))
  (setq lispy-python-proc (format "Python:ob-ipython-%s" (->> info (nth 2) (assoc :session) cdr
                                                              ob-ipython--normalize-session)))
  (setq-local
   default-directory (format "%s" (->> info (nth 2) (assoc :pydir) cdr
                                       ob-ipython--normalize-session)))
  (ob-ipython-mode 1)
  (setq lispy--python-middleware-loaded-p nil)
  (setq-local company-idle-delay nil)
  (setq company-backends '(company-capf company-dabbrev company-files company-yasnippet))
  (lispy--python-middleware-load))

;;;###autoload
(defun ob-ipython-generate-local-path-from-remote (session host params)
  "Copy remote config to local, start a jupyter console to generate a new one."
  (let* ((runtime-dir (substring (shell-command-to-string
                                  (concat "ssh " host " jupyter --runtime-dir")) 0 -1))
         (runtime-file (concat runtime-dir "/" "kernel-" session ".json"))
         (tramp-path (concat "/ssh:" host ":" runtime-file))
         (tramp-copy (concat jupyter-local-runtime-dir "/remote-" host "-kernel-" session ".json"))
         (local-path (concat "Python:ob-ipython-" (file-name-sans-extension (file-name-nondirectory tramp-copy)) "-ssh.json")))
    ;; scp remote file to local
    (copy-file tramp-path tramp-copy t)
    ;; connect to remote use new config
    (let* ((python-shell-interpreter-interactive-arg " console --simple-prompt")
           (python-shell-completion-native-enable nil)
           (buf (python-shell-make-comint
                 (concat ob-ipython-command " console --simple-prompt --existing " tramp-copy " --ssh " host)
                 (concat "" local-path) t))
           (proc (get-buffer-process buf))
           (dir (cdr (assoc :pydir params))))
      (sleep-for 3)
      (if dir (with-current-buffer buf
                (setq-local default-directory dir)))
      (format "*%s*" proc))))
