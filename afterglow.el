;;; afterglow.el --- Temporary Highlighting after Function Calls

;; Author: Ernest M. van der Linden  <hello@ernestoz.com>
;; Version: 0.2.1
;; Package-Requires: ((emacs "26.1"))
;; Keywords: highlight, line, convenience, evil
;; URL: https://github.com/ernestvanderlinden/emacs-afterglow

;; This file is not part of GNU Emacs.

;;; License:

;; MIT License
;;
;; Copyright (c) 2024 Ernest M. van der Linden
;;
;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:
;;
;; The above copyright notice and this permission notice shall be included in all
;; copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.

;;; Commentary:

;;Other related packages:
;; - `beacon-mode': on window scroll line highlighting;
;; - `hl-line-mode': permanent line highlighting.
;;
;; `afterglow' uses the `hl-line' face defined in `hl-line-mode' as default.

;;; Usage:

;; (require 'afterglow)
;; (afterglow-mode t)
;; 
;; Things:
;; Afterglow allows highlighting based on different 'things', including:
;; - Custom Function: Implement your own function which returns a cons
;; cell containing the beginning and end of a region e.g. (234 . 543)
;; - Region: If a region is active, that region will be highlighted
;; - Line: Add a property `:width` to control the length of the line
;; - Window: Highlights the current window
;;
;; Other `Things` as defined in the `thingatpt' package: symbol, list,
;; sexp, defun, number, filename, url, email, uuid, word, sentence,
;; whitespace and page.
;;
;; Customize `afterglow-default-duration` to adjust the duration of the highlight.
;; For example, to set the highlight to disappear after 0.5 seconds, use:
;;
;; (setq afterglow-default-duration 0.5)
;; 
;; Customize `afterglow-default-face' to change the highlight appearance:
;;
;; (setq afterglow-default-face 'your-custom-face)
;;
;; See M-x `describe-face' for possible face symbols.
;;
;; To toggle temporary line highlighting on and off:
;;
;; M-x afterglow-mode
;;
;; Public Functions:
;; afterglow-add-trigger
;; afterglow-add-triggers
;; afterglow-mode
;; afterglow-remove-trigger
;; afterglow-remove-triggers
;;
;; Public Vars:
;; afterglow-duration
;; afterglow-face
;; afterglow-mode
;; afterglow-mode-hook
;;
;; Example 1:
;; (require 'afterglow)
;; (afterglow-mode t)
;;
;; ;; Optional
;; (setq afterglow-default-duration 0.5)
;; ;; Optional
;; (setq afterglow-default-face 'hl-line)
;;
;; (afterglow-add-triggers
;;  '((evil-previous-visual-line :thing line :width 5 :duration 0.2)
;;    (evil-next-visual-line :thing line :width 5 :duration 0.2)
;;    (previous-line :thing line :duration 0.2)
;;    (next-line :thing line :duration 0.2)
;;    (eval-buffer :thing window :duration 0.2)
;;    (eval-defun :thing defun :duration 0.2)
;;    (eval-expression :thing sexp :duration 1)
;;    (eval-last-sexp :thing sexp :duration 1)
;;    (my-function :thing my-region-function :duration 0.5
;;                 :face 'highlight)))
;;
;; Example 2: use let binding instead
;; (let ((width 5)
;;       (duration 0.3))
;;   (afterglow-add-triggers
;;    `((evil-previous-visual-line :thing line :width ,width
;;                                 :duration ,duration)
;;      (evil-next-visual-line :thing line :width ,width
;;                             :duration ,duration)
;;      (previous-line :thing line :duration ,duration)
;;      (next-line :thing line :duration ,duration)
;;      (eval-buffer :thing window :duration ,duration)
;;      (eval-defun :thing defun :duration ,duration)
;;      (eval-region :thing region :duration ,duration
;;                   :face (:background "green"))
;;      (eval-last-sexp :thing sexp :duration ,duration))))

;;; Code:

(eval-when-compile
  (require 'thingatpt)
  (require 'subr-x))

(defgroup afterglow nil
  "Customization group for afterglow."
  :group 'convenience)

(defcustom afterglow-default-duration 1
  "Duration in seconds before removing the overlay."
  :type 'number
  :group 'afterglow)

(defcustom afterglow-default-face 'hl-line
  "Face used for line highlighting."
  :type 'face
  :group 'afterglow)

(defvar afterglow--temp-overlay nil
  "Overlay for temporary highlighting.")

(defvar afterglow--triggers (make-hash-table :test 'equal)
  "Hash table storing properties for advised functions.")

;;; TRIGGER

(defun afterglow--add-trigger (fn args)
  "Set up a trigger function FN with properties specified in ARGS."
  (afterglow--advices-remove-unused)
  (puthash fn args afterglow--triggers))

(defun afterglow-add-trigger (fn &rest args)
  "Add a trigger function FN to be advised with properties.

Example:
\(afterglow-add-trigger \='evil-previous-visual-line
                       :thing \='line :width 5 :duration 0.2)
Optional argument ARGS adsf."
  (afterglow--add-trigger fn args)
  (afterglow--enable))

(defun afterglow-add-triggers (triggers)
  "Add multiple triggers at once.

TRIGGERS is a list where each element is a list containing the
function symbol followed by keyword arguments for additional
properties.

Example 1:

\(afterglow-add-triggers
 \='((evil-previous-visual-line :thing line :width 5 :duration 0.2)
   (evil-next-visual-line :thing line :width 5 :duration 0.2)
   (previous-line :thing line :duration 0.2)
   (next-line :thing line :duration 0.2)
   (eval-buffer :thing window :duration 0.2)
   (eval-defun :thing defun :duration 0.2)
   (eval-expression :thing sexp :duration 1)
   (eval-last-sexp :thing sexp :duration 1)
   (my-function :thing \='my-region-function :duration 0.5
                :face \='highlight)))

;; Example 2: use let binding instead
\(let ((width 5)
      (duration 0.3))
  (afterglow-add-triggers
   `((evil-previous-visual-line :thing line :width ,width
                                :duration ,duration)
     (evil-next-visual-line :thing line :width ,width
                            :duration ,duration)
     (previous-line :thing line :duration ,duration)
     (next-line :thing line :duration ,duration)
     (eval-buffer :thing window :duration ,duration)
     (eval-defun :thing defun :duration ,duration)
     (eval-region :thing region :duration ,duration
                  :face (:background \"green\"))
     (eval-last-sexp :thing sexp :duration ,duration))))"

  (dolist (trigger triggers)
    (let ((fn (car trigger))
          (args (cdr trigger)))
      (afterglow--add-trigger fn args)))
  (afterglow--enable))

(defun afterglow--remove-trigger (fn)
  "Remove a single trigger and its associated advice.
Argument FN ."
  (let ((advice-fn-symbol (afterglow--advice-fn-symbol fn)))
    (remhash fn afterglow--triggers)
    (afterglow--advice-remove fn advice-fn-symbol)))

(defun afterglow-remove-trigger (fn)
  "Remove a single trigger and its associated advice.

Example:
\(afterglow-remove-trigger \='evil-previous-visual-line)
Argument FN ."
  (afterglow--remove-trigger fn))

(defun afterglow-remove-triggers (fn-list)
  "Remove multiple triggers and their associated advice.
  
Example:

\(afterglow-add-triggers
\='(evil-previous-visual-line
    evil-previous-visual-line
    evil-previous-line
    evil-next-visual-line))
Argument FN-LIST ."

  (dolist (fn fn-list)
    (afterglow--remove-trigger fn)))

(defun afterglow--trigger-functions ()
  "Return a list of functions that have been added as triggers."
  (hash-table-keys afterglow--triggers))

(defun afterglow--advice-fn-symbol (fn)
  "Generate an advice function name symbol for FN."
  (intern (concat "afterglow--after-trigger-" (symbol-name fn))))

;;; ADVICE

(defvar afterglow--advised-functions '()
  "List of pairs (FN . ADVICE-FN-SYMBOL) for functions advised.
We use this to cleanup advice left overs")

(defun afterglow--advice-add (fn advice-fn-symbol)
  "Add advice to FN with ADVICE-FN-SYMBOL and track it."
  (unless (fboundp advice-fn-symbol)
    (fset advice-fn-symbol
          `(lambda (&rest _args)
             (let ((properties (gethash ',fn afterglow--triggers)))
               (when properties
                 (afterglow--apply-overlay properties)))))
    (advice-add fn :after advice-fn-symbol)
    (push (cons fn advice-fn-symbol) afterglow--advised-functions)))

(defun afterglow--advice-remove (fn advice-fn-symbol)
  "Remove advice from FN identified by ADVICE-FN-SYMBOL and untrack."
  (when (fboundp advice-fn-symbol)
    (advice-remove fn advice-fn-symbol)
    (fmakunbound advice-fn-symbol))
  (setq afterglow--advised-functions
        (assq-delete-all fn afterglow--advised-functions)))

(defun afterglow--advice-remove-all ()
  "Remove all advices added by Afterglow."
  (dolist (pair afterglow--advised-functions)
    (let ((fn (car pair))
          (advice-fn-symbol (cdr pair)))
      (afterglow--advice-remove fn advice-fn-symbol)))
  (setq afterglow--advised-functions '()))

(defun afterglow--advices-remove-unused ()
  "Cleanup unused trigger functions and their advices."
  (dolist (pair afterglow--advised-functions)
    (let ((fn (car pair))
          (advice-fn-symbol (cdr pair)))
      ;; Still a valid trigger?
      (unless (gethash fn afterglow--triggers)
        (afterglow--advice-remove fn advice-fn-symbol)
        (fmakunbound advice-fn-symbol))))
  ;; Clean tracking list of any entries that have been unbound.
  (setq afterglow--advised-functions
        (cl-remove-if-not (lambda (pair) (fboundp (cdr pair)))
                          afterglow--advised-functions)))

(defun afterglow--advices-remove-all (unbind-functions-p)
  "Cleanup all advices added by Afterglow, optionally unbinding the functions.
UNBIND-FUNCTIONS-P, when non-nil, also unbinds the advised functions."
  (dolist (pair afterglow--advised-functions)
    (let ((fn (car pair))
          (advice-fn-symbol (cdr pair)))
      ;; Always remove the advice.
      (afterglow--advice-remove fn advice-fn-symbol)
      ;; Optionally unbind function, based on UNBIND-FUNCTIONS-P.
      (when unbind-functions-p
        (fmakunbound advice-fn-symbol))))
  ;; Clear tracking list as all functions have been processed.
  (setq afterglow--advised-functions '())
  (message "afterglow--advices-remove-all done. Functions %sunbound."
           (if unbind-functions-p "" "not ")))

;;; ENABLE/DISABLE

(defun afterglow--reset ()
  "Disable and enable afterglow."
  (afterglow--disable)
  (afterglow--enable))

(defun afterglow--enable ()
  "Enable advising functions for highlighting."
  (afterglow--advices-remove-unused)
  (dolist (fn (afterglow--trigger-functions))
    (when (fboundp fn)
      (afterglow--advice-add fn (afterglow--advice-fn-symbol fn)))))

(defun afterglow--disable ()
  "Disable advising functions and remove highlight.
\(afterglow-cleanup-advices nil) ; Remove advice, don't unbind triggers
\(afterglow-cleanup-advices t) ; Remove advice and unbind triggers"
  (afterglow--remove-overlays)
  (afterglow--advice-remove-all))

;;; OVERLAY

(defun afterglow--remove-overlays ()
  "Remove all afterglow overlays from the current buffer."
  (remove-overlays nil nil 'afterglow t))

(defun afterglow--apply-overlay (properties)
  "Apply an overlay based on PROPERTIES."
  (let* ((thing (plist-get properties :thing))
         (width (plist-get properties :width))
         (duration (or (plist-get properties :duration) afterglow-default-duration))
         (face (or (plist-get properties :face) afterglow-default-face)))
    
    ;; Remove existing overlay
    (when afterglow--temp-overlay
      (delete-overlay afterglow--temp-overlay))

    (let ((beg nil) (end nil))

      ;; Which thing?
      (cond
       ;; Function?
       ((functionp thing)
        (let ((bounds (funcall thing)))
          (setq beg (car bounds)
                end (cdr bounds))))

       ;; Region?
       ((eq thing 'region)
        (let ((bounds (car (region-bounds))))
          (when bounds
            (setq beg (car bounds)
                  end (cdr bounds)))))

       ;; Line
       ((eq thing 'line)
        (unless (afterglow--current-line-empty-p)
          (setq beg (line-beginning-position)
                end (if width
                        (min (+ beg width) (line-end-position))
                      (line-end-position)))))

       ;; Window
       ((eq thing 'window)
        (let ((win (get-buffer-window (current-buffer) t)))
          (setq beg (window-start win)
                end (window-end win t))))

       ;; Default case for other things like 'word, 'sentence', etc.
       (t
        (let ((bounds (bounds-of-thing-at-point thing)))
          (setq beg (car bounds)
                end (cdr bounds)))))

      ;; Create and apply the overlay.
      (when (and beg end)
        (setq afterglow--temp-overlay (make-overlay beg end))
        (overlay-put afterglow--temp-overlay 'face face)
        ;; Set high priority in case a `region' has been selected
        (overlay-put afterglow--temp-overlay 'priority 100)

        ;; Schedule the overlay to be automatically removed after the specified duration
        (run-with-timer duration nil
                        (lambda ()
                          (delete-overlay afterglow--temp-overlay)))))))

;; THING should be a symbol specifying a type of syntactic entity.
;; Possibilities include `symbol', `list', `sexp', `defun', `number',
;; `filename', `url', `email', `uuid', `word', `sentence', `whitespace',
;; `line', and `page'.

;; UTILS

(defun afterglow--current-line-empty-p ()
  "True if the current line is empyty."
  (save-excursion
    (beginning-of-line)
    (looking-at-p "^[[:space:]]*$")))

;;; MODE

(define-minor-mode afterglow-mode
  "Toggle Afterglow mode."
  :global nil
  :lighter " afterglow"
  (if afterglow-mode
      (afterglow--enable)
    (afterglow--disable)))

(provide 'afterglow)

;;; afterglow.el ends here
