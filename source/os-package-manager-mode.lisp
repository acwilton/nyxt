;;;; SPDX-FileCopyrightText: Atlas Engineer LLC
;;;; SPDX-License-Identifier: BSD-3-Clause

(uiop:define-package :nyxt/os-package-manager-mode
  (:use :common-lisp :trivia :nyxt)
  (:import-from #:keymap #:define-key #:define-scheme)
  (:documentation "Universal interface to various operating system package managers."))
(in-package :nyxt/os-package-manager-mode)

;; TODO: Prompt for password?  Use this:
;; (with-input-from-string (i "password")
;;   (uiop:run-program '("sudo" "-S" "ls" "-la" "/root")
;;                     :output '(:string) :input i))

(define-mode os-package-manager-mode ()
  "Mode for package management."
  ((current-process-info nil
                         :type (or null uiop/launch-program::process-info))
   (keymap-scheme
    (define-scheme "web"
      scheme:cua
      (list
       "C-d" 'cancel-package-operation)
      scheme:emacs
      (list
       "C-d" 'cancel-package-operation)
      scheme:vi-normal
      (list
       "C-d" 'cancel-package-operation)))))

(define-command cancel-package-operation ()
  "Terminate the package manager process in the current buffer."
  (serapeum:and-let* ((process-info (current-process-info
                                     (find-submode (current-buffer) 'os-package-manager-mode))))
    (uiop:terminate-process process-info)
    (ffi-buffer-evaluate-javascript-async
     (current-buffer)
     (ps:ps (ps:chain document
                      (write (ps:lisp (markup:markup (:p "Operation cancelled.")))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(in-package :nyxt)

(defmethod object-string ((pkg ospm:os-package))
  (ospm:name pkg))
(defmethod object-display ((pkg ospm:os-package))
  (format nil "~a ~a~a~a"
          (ospm:name pkg)
          (ospm:version pkg)
          (make-string (max 1 (- 40
                                 (+ (length (ospm:name pkg))
                                    (length (ospm:version pkg)))))
                       :initial-element #\ )
          (ospm:synopsis pkg)))

(defmethod object-string ((output ospm:os-package-output))
  (format nil "~a:~a"
          (ospm:name (ospm:parent-package output))
          (ospm:name output)))
(defmethod object-display ((output ospm:os-package-output))
  (let* ((pkg (ospm:parent-package output))
         (name (format nil "~a~a ~a"
                       (ospm:name pkg)
                       ;; TODO: Make this specializable.
                       (if (string= (ospm:name output) "out")
                           ""
                           (str:concat ":" (ospm:name output)))
                       (ospm:version pkg))))
    (format nil "~a~a~a"
            name
            (make-string (max 1 (- 40 (length name)))
                         :initial-element #\ )
            (ospm:synopsis pkg))))

(defmethod object-string ((gen ospm:os-generation))
  (ospm:id gen))
(defmethod object-display ((gen ospm:os-generation))
  (format nil "~a ~a ~a packages~a"
          (ospm:id gen)
          (local-time:format-timestring nil (ospm:date gen)
                                        :format local-time:+asctime-format+)
          (ospm:package-count gen)
          (if (ospm:current? gen)
              " (current)"
              "")))

(defun os-package-suggestion-filter ()
  (echo "Loading package database...")
  (let* ((all-packages (ospm:list-packages)))
    (echo "")
    (lambda (minibuffer)
      (fuzzy-match (input-buffer minibuffer) all-packages))))

(defun os-manifest-suggestion-filter ()
  (let* ((all-manifests (mapcar #'namestring (ospm:list-manifests))))
    (lambda (minibuffer)
      (fuzzy-match (input-buffer minibuffer) all-manifests))))

(defun os-package-output-suggestion-filter ()
  (echo "Loading package database...")
  (let* ((all-outputs (ospm:list-package-outputs)))
    (echo "")
    (lambda (minibuffer)
      (fuzzy-match (input-buffer minibuffer) all-outputs))))

(defun os-installed-package-suggestion-filter (profile)
  (let* ((installed-packages (ospm:list-packages profile)))
    (lambda (minibuffer)
      (fuzzy-match (input-buffer minibuffer) installed-packages))))

(defun os-profile-suggestion-filter (&key include-manager-p)
  (let* ((all-profiles (ospm:list-profiles :include-manager-p include-manager-p)))
    (lambda (minibuffer)
      ;; TODO: Don't prompt when there is just 1 profile.
      (fuzzy-match (input-buffer minibuffer) all-profiles))))

(defun os-generation-suggestion-filter (profile)
  (let* ((all-generations (ospm:list-generations profile)))
    (lambda (minibuffer)
      ;; TODO: Don't prompt when there is just 1 profile.
      (fuzzy-match (input-buffer minibuffer) all-generations))))

(defun %describe-os-package (packages)
  (let* ((buffer (or (find-buffer 'os-package-manager-mode)
                     (nyxt/os-package-manager-mode:os-package-manager-mode
                      :activate t
                      :buffer (make-internal-buffer :title "*OS packages*")))))
    (flet ((format-inputs (inputs)
             (alex:mappend
              (lambda (input)
                `((:a :href (lisp-url
                             '(%describe-os-package
                               (ospm:find-os-packages ,input)))
                      ,input)
                  " "))
              inputs))
           (format-outputs (outputs)
             `(:div
               (:table
                ,@(alex:mappend
                   (lambda (output)
                     `((:tr
                        (:td ,(ospm:name output))
                        ,@(when (ospm:expanded-output-p output)
                            `((:td
                               ,(sera:format-file-size-human-readable
                                 nil
                                 (ospm:size output)))
                              (:td ,(ospm:path output)))))))
                   outputs))
               ,@(when (and (<= 2 (length outputs))
                            (ospm:expanded-output-p (first outputs)))
                   `((:li "Total size: " ,(sera:format-file-size-human-readable
                                           nil
                                           (reduce #'+ (mapcar #'ospm:size outputs)))))))))
      (html-set
       (markup:markup
        (:style (style buffer))
        (:h1 "Packages")
        (:ul
         (loop for package in packages
               collect (markup:markup*
                        `(:li ,(ospm:name package) " " ,(ospm:version package)
                              (:ul
                               ,@(when (typep package 'ospm:guix-package)
                                   `((:li "Outputs: "
                                          ,@(unless (ospm:expanded-outputs-p package)
                                              `((:a :class "button"
                                                    :href ,(lisp-url '(echo "Computing path & size...")
                                                                     `(ospm:expand-outputs (first (ospm:find-os-packages
                                                                                                     ,(ospm:name package)
                                                                                                     :version ,(ospm:version package))))
                                                                     `(%describe-os-package
                                                                       (ospm:find-os-packages ,(ospm:name package)
                                                                                                :version ,(ospm:version package))))
                                                    "Compute path & size")))
                                          ,(format-outputs (ospm:outputs package)))
                                     (:li "Supported systems: " ,(str:join " " (ospm:supported-systems package)))
                                     (:li "Inputs: " ,@(format-inputs (ospm:inputs package)))
                                     (:li "Propagated inputs: " ,@(format-inputs (ospm:propagated-inputs package)))
                                     (:li "Native inputs: " ,@(format-inputs (ospm:native-inputs package)))
                                     (:li "Location: " ,(ospm:location package))))
                               (:li "Home-page: " (:a :href ,(ospm:home-page package)
                                                      ,(ospm:home-page package)))
                               (:li "Licenses: " ,(str:join ", " (ospm:licenses package)))
                               (:li "Synopsis: " ,(ospm:synopsis package))
                               ,(when (typep package 'ospm:guix-package)
                                  `(:li "Description: " ,(ospm:description package)))))))))
       buffer))
    (set-current-buffer buffer)
    buffer))

(defun assert-package-manager ()
  (unless (ospm:manager)
    (let ((message "No supported package manager detected."))
      (echo message)
      (error message))))

(define-command describe-os-package ()
  "Show description of select packages."
  (assert-package-manager)
  (let* ((packages (prompt-minibuffer
                    :suggestion-function (os-package-suggestion-filter)
                    :input-prompt "Describe OS package(s)"
                    :multi-selection-p t)))
    (%describe-os-package packages)))

(defun viewable-file-type-p (path)
  (let ((path-suffix (string-downcase (namestring path))))
    (some (lambda (suffix)
            (str:ends-with? path-suffix suffix) )
          '(".html" ".htm") )))

;; TODO: open in editor, with select program, leverage file-manager
(define-command list-os-package-files ()
  "List files of select packages."
  (assert-package-manager)
  (let* ((packages-or-outputs (if (typep (ospm:manager) 'ospm:guix-manager)
                                  (prompt-minibuffer
                                   :suggestion-function (os-package-output-suggestion-filter)
                                   :input-prompt "List files of OS package outputs(s)"
                                   :multi-selection-p t)
                                  (prompt-minibuffer
                                   :suggestion-function (os-package-suggestion-filter)
                                   :input-prompt "List files of OS package(s)"
                                   :multi-selection-p t)))
         (buffer (or (find-buffer 'os-package-manager-mode)
                     (nyxt/os-package-manager-mode:os-package-manager-mode
                      :activate t
                      :buffer (make-internal-buffer :title "*OS packages*")))))
    (echo "Computing file list...")
    (html-set
     (markup:markup
      (:style (style buffer))
      (:h1 "Package files")
      (:ul
       (loop for package-or-output in packages-or-outputs
             collect (markup:markup*
                      `(:li ,(object-string package-or-output)
                            (:ul
                             ,@(mapcar (lambda (file)
                                         `(:li ,(if (viewable-file-type-p file)
                                                    `(:a :href ,file ,file)
                                                    file)))
                                       (ospm:list-files (list package-or-output)))))))))
     buffer)
    (echo "")
    (set-current-buffer buffer)
    buffer))

(defun format-command-stream (process-info callback)
  (loop for object = (read-line (uiop:process-info-output process-info) nil :eof)
        until (eq object :eof)
        do (funcall callback object)))

(defun operate-os-package (title command profile objects)
  "Run COMMAND over OBJECTS in PROFILE.
OBJECTS can be a list of packages, a generation, etc."
  (let* ((buffer (or (find-buffer 'os-package-manager-mode)
                     (nyxt/os-package-manager-mode:os-package-manager-mode
                      :activate t
                      :buffer (make-internal-buffer :title "*OS packages*")))))
    (if (sera:and-let* ((process-info (nyxt/os-package-manager-mode:current-process-info
                                       (find-submode buffer 'os-package-manager-mode))))
          (uiop:process-alive-p process-info))
        (echo "An package operation is already running.  You can cancel it with `cancel-package-operation'.")
        (progn
          (pexec ()
            (let ((process-info (funcall command objects profile))
                  (mode (find-submode buffer 'os-package-manager-mode)))
              (setf (nyxt/os-package-manager-mode:current-process-info mode) process-info)
              (html-set "" buffer)      ; Reset content between operations.
              (html-write
               (markup:markup
                (:style (style buffer))
                (:h1 title)
                (:p
                 (:a :class "button"
                     :href (lisp-url '(nyxt/os-package-manager-mode:cancel-package-operation))
                     "Cancel")))
               buffer)
              (format-command-stream
               process-info
               (lambda (s)
                 ;; TODO: Make shell formating function and add support for
                 ;; special characters, e.g. progress bars.
                 (html-write
                  (markup:markup
                   (:code (str:replace-all " " " " s))
                   (:br))
                  buffer)))
              (html-write
               (markup:markup (:p "Done."))
               buffer)))
          (set-current-buffer buffer)
          buffer))))

(define-command install-os-package ()
  "Install select packages."
  (assert-package-manager)
  ;; TODO: Allow profile creation.  Need multi-source support for that?
  (let* ((profile (prompt-minibuffer
                   :suggestion-function (os-profile-suggestion-filter)
                   :input-prompt "Target profile"))
         (packages (prompt-minibuffer
                    :suggestion-function (os-package-output-suggestion-filter)
                    :input-prompt "Install OS package(s)"
                    :multi-selection-p t)))
    (operate-os-package "Installing packages..." #'ospm:install profile packages)))

(define-command uninstall-os-package ()
  "Uninstall select packages."
  (assert-package-manager)
  (let* ((profile (prompt-minibuffer
                   :suggestion-function (os-profile-suggestion-filter)
                   :input-prompt "Target profile"))
         (packages (prompt-minibuffer
                    :suggestion-function (os-installed-package-suggestion-filter profile)
                    :input-prompt "Uninstall OS package(s)"
                    :multi-selection-p t)))
    (operate-os-package "Uninstalling packages..." #'ospm:uninstall profile packages)))

(define-command install-package-manifest ()
  "Install select manifest to a profile."
  (assert-package-manager)
  (let* ((profile (prompt-minibuffer
                   :suggestion-function (os-profile-suggestion-filter)
                   :input-prompt "Target profile"))
         (manifest (prompt-minibuffer
                    :suggestion-function (os-manifest-suggestion-filter)
                    :input-prompt "Manifest")))
    (operate-os-package "Installing package manifest..." #'ospm:install-manifest profile manifest)))

(define-command edit-package-manifest ()
  "Edit select manifest."
  (assert-package-manager)
  (let ((manifest (prompt-minibuffer
                   :suggestion-function (os-manifest-suggestion-filter)
                   :input-prompt "Manifest")))
    (echo "Opening ~s with ~a" manifest (external-editor-program *browser*))
    (uiop:launch-program (list (external-editor-program *browser*) manifest))))

(define-command describe-os-generation ()
  "Show the packages of a given profile generation."
  (assert-package-manager)
  (let* ((profile (prompt-minibuffer
                   :suggestion-function (os-profile-suggestion-filter
                                         :include-manager-p t)
                   :input-prompt "Profile"))
         (generation (prompt-minibuffer
                      :suggestion-function (os-generation-suggestion-filter profile)
                      :input-prompt "Generation"))
         (buffer (or (find-buffer 'os-package-manager-mode)
                     (nyxt/os-package-manager-mode:os-package-manager-mode
                      :activate t
                      :buffer (make-internal-buffer :title "*OS packages*")))))
    (echo "Loading package database...")
    (html-set
     (markup:markup
      (:style (style buffer))
      (:h2 (format nil "Packages for generation ~a" (ospm:id generation)))
      (:p "Profile " profile)
      (:ul
       (loop for package-output in (ospm:list-packages (ospm:path generation))
             for package = (ospm:parent-package package-output)
             collect
             (markup:markup*
              `(:li (:a :class "button"
                        :href ,(lisp-url `(%describe-os-package
                                           (or (ospm:find-os-packages
                                                ,(ospm:name package)
                                                :version ,(ospm:version package))
                                               (ospm:find-os-packages
                                                ,(ospm:name package)))))
                        ,(object-string package-output))
                    " " ,(ospm:version package))))))
     buffer)
    (echo "")
    (set-current-buffer buffer)
    buffer))

(define-command switch-os-generation ()
  "Switch generation of selected profile."
  (assert-package-manager)
  (let* ((profile (prompt-minibuffer
                   :suggestion-function (os-profile-suggestion-filter
                                         :include-manager-p t)
                   :input-prompt "Target profile"))
         (generation (prompt-minibuffer
                      :suggestion-function (os-generation-suggestion-filter profile)
                      :input-prompt "Switch to generation")))
    (operate-os-package "Switching to generation..." #'ospm:switch-generation
                        profile generation)))

(define-command delete-os-generations ()
  "Delete generations of selected profile."
  (assert-package-manager)
  (let* ((profile (prompt-minibuffer
                   :suggestion-function (os-profile-suggestion-filter
                                         :include-manager-p t)
                   :input-prompt "Target profile"))
         (generations (prompt-minibuffer
                       :suggestion-function (os-generation-suggestion-filter profile)
                       :input-prompt "Delete generations"
                       :multi-selection-p t)))
    (operate-os-package "Deleting generations..." #'ospm:delete-generations
                        profile generations)))

;; TODO: Parse Texinfo for Guix descriptions.
;; TODO: Add commands:
;; - show-deps, show-reverse-deps (when minibuffer has actions)
