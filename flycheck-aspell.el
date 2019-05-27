;;; flycheck-aspell --- simple spell check using flycheck and aspell -*- lexical-binding: t; -*-

;; Author: Leo Gaskin <leo.gaskin@brg-feldkirchen.at>
;; Created: 26 May 2019
;; Homepage: https://github.com/leotaku/flycheck-aspell
;; Keywords: flycheck, spell, aspell
;; Package-Version: 0.1.0
;; Package-Requires: ((flycheck "31") (emacs "25.1"))

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <https://www.gnu.org/licenses/>.

;;; Commentary

;; * flycheck-aspell :README:

;; ![[file:screenshot.png][flycheck-aspell in action]]

;; This package adds support for spell checking to flycheck using
;; the [[http://aspell.net][GNU aspell]] application.

;; It is a successor (and complete rewrite) to my
;; [[https://github.com/leotaku/flycheck-hunspell][flycheck-hunspell]]
;; project, which was crippled by the bad performance of hunspell when
;; used with larger files.
;; (aspell performs aproximately 30x faster in the cases I tested.)

;; Aspell also seems to be a bit more flexible than hunspell with regard
;; to filters, which might prove to be useful in the future.

;; ** Installation

;; I recommend using [[https://github.com/raxod502/straight.el][straight.el]] for
;; installing non-(m)elpa sources.

;; ** Usage

;; Simply register your preferred checkers with flycheck.
;; (see [[Features]] for supported filetypes)

;; #+begin_src elisp
;; (require 'flycheck-aspell)
;; (add-to-list 'flycheck-checkers 'tex-aspell-generic)
;; #+end_src

;; The dictionary the checkers use is determined by the value of
;; `ispell-local-dictionary` or `ispell-dictionary`.

;; It might be wise to skim the [[https://www.flycheck.org/en/latest/][flycheck docs]]
;; to learn how to efficently use and configure flycheck.

;; You of course also need to install the =aspell= binary.
;; All major linux distributions package it and there's probably
;; a working macport or something.

;; ** Configuration

;; For steamless ispell integration, I recommend setting the following variables:

;; #+begin_src elisp
;; (setq ispell-dictionary "some_dictionary"
;;       ispell-program-name "aspell"
;; 	 ispell-silently-savep t)
;; #+end_src

;; [[https://blog.binchen.org/posts/what-s-the-best-spell-check-set-up-in-emacs.html][This post]]
;; might also be of interest.

;; You may also want to advice `ispell-pdict-save` for instant feedback when inserting
;; new entries into your local dictionary:
 
;; #+begin_src elisp
;; (advice-add 'ispell-pdict-save :after 'flycheck-maybe-recheck)
;; (defun flycheck-maybe-recheck (_)
;;   (when (bound-and-true-p flycheck-mode)
;;    (flycheck-buffer))
;; #+end_src

;; ** TODO Features

;; + [X] initial featureset
;; + [ ] checkers for all filters
;;   - [X] TeX
;;   - [ ] plain (url support)
;;   - [ ] nroff
;;   - [ ] html
;;   - [ ] ...
;; + [ ] tests
;; + [X] honor ispell localwords (they are marked as info)

;; * bottom footer :code:

(require 'flycheck)
(require 'ispell)

;; (flycheck-define-checker plain-aspell-generic
;;   "A spell checker for plain text files using aspell."
;;   :command ("aspell" "pipe"
;; 	    "-d" (eval (or ispell-local-dictionary
;; 			   ispell-dictionary
;; 			   "en_US"))
;; 	    "--add-filter" "url")
;;   :standard-input t
;;   :error-parser flycheck-parse-aspell
;;   :modes (org-mode ))

;; (flycheck-define-checker tex-aspell-generic
;;   "A spell checker for TeX files using aspell."
;;   :command ("aspell" "pipe"
;; 	    "-d" (eval (or ispell-local-dictionary
;; 			   ispell-dictionary
;; 			   "en_US"))
;; 	    "--add-filter" "tex")
;;   :standard-input t
;;   :error-parser flycheck-parse-aspell
;;   :modes (tex-mode latex-mode context-mode))

(defun flycheck-run-aspell (checker callback)
  (with-demoted-errors "Error: %s"
    (let ((buffer (current-buffer))
	  (buffer-string (buffer-string)))
      ;; (message "test: Checker is run")
      (async-start
       `(lambda ()
	
	  (defun flycheck-parse-aspell2 (output checker buffer-string)
	    (let ((final-return nil)
		  (line-number 1)
		  (buffer-lines
		   (split-string buffer-string "\n"))
		  (error-structs
		   (mapcar 'flycheck-aspell-handle-line
			   (split-string output "\n"))))
	      (dolist (struct error-structs)
		(unless (null struct)
		  (let* ((word (nth 0 struct))
			 (column (nth 1 struct))
			 (suggestions (nth 2 struct)))
		    (while (not (or (null (cdr buffer-lines))
				    (string-match-p
				     word
				     ;; (concat
				     ;;  (rx (or (not letter) line-start))
				     ;;  word
				     ;;  (rx (or (not letter) line-start)))
				     (car buffer-lines))))
		      (setq buffer-lines (cdr buffer-lines))
		      (setq line-number (1+ line-number)))
		    ;; (message "%s: %s" word line-number)
		    ;; FIXME: aspell seemingly sometimes reports
		    ;; (message "%s at %s/%s: %s" word line-number column (car buffer-lines))
		    ;; (setf (car buffer-lines)
		    ;; 	(concat (make-string (+ column (length word) 1) ?=)
		    ;; 		(substring (car buffer-lines)
		    ;; 			   (+ (+ column (length word)) 0))))
		    (push
		     `(flycheck-error-new-at
		       ,line-number ,(1+ column)
		       (if (member ,word ispell-buffer-session-localwords)
			   'info 'error)
		       ,(if (null suggestions)
			    (concat "Unknown: " word)
			  (concat "Suggest: " word " -> " suggestions))
		       :checker ',checker
		       :buffer (current-buffer)
		       :filename (buffer-file-name (current-buffer)))
		     final-return))))
	      final-return))

	  (defun flycheck-aspell-handle-line (line)
	    (cond
	     ;; # indicates that no replacement could be found
	     ((string-match-p "^#" line)
	      (flycheck-aspell-handle-hash line))
	     ;; & indicates that replacements could be found
	     ((string-match-p "^&" line)
	      (flycheck-aspell-handle-and line))
	     ;; other lines are irrelevant
	     (t
	      nil)))

	  (defun flycheck-aspell-handle-hash (line)
	    (string-match
	     (rx line-start "# "	; start
		 (group (+ char)) " "	; error
		 (group (+ digit)))	; column
	     line)
	    (let ((word (match-string 1 line))
		  (column (match-string 2 line)))
	      (list word (string-to-number column) nil)))

	  (defun flycheck-aspell-handle-and (line)
	    (string-match
	     (rx line-start "& "	; start
		 (group (+ char)) " "	; error
		 (+ digit) " "		; suggestion count
		 (group (+ digit)) ": " ; column
		 (group (+? anything)) line-end)
	     line)
	    (let ((word (match-string 1 line))
		  (column (match-string 2 line))
		  (suggestions (match-string 3 line)))
	      (list word (string-to-number column) suggestions)))
	
	  (let ((aspell-output
		 (with-temp-buffer
    		   (call-process-region
    		    ,buffer-string nil
    		    "aspell"
    		    nil t nil
    		    "pipe" "-d" "en_US")
    		   (buffer-string))))
	    (flycheck-parse-aspell2 aspell-output ',checker ,buffer-string)))
       `(lambda (return)
	  ;; (message "test: %S" (mapcar 'eval return))
	  (with-current-buffer ,buffer
	    (funcall ,callback 'finished (mapcar 'eval return))))))))

(flycheck-define-generic-checker 'tex-aspell-generic2
  "A spell checker for TeX files using aspell."
  :start 'flycheck-run-aspell
  :modes '(markdown-mode))

(provide 'flycheck-aspell)
