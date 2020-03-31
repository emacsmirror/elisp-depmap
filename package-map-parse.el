;;; package-map-parse.el --- Construct a hashtable of top level definitions -*- lexical-binding: t; -*-

;; Copright (C) 2020 Mehmet Tekman <mtekman89@gmail.com>

;; Author: Mehmet Tekman
;; URL: https://github.com/mtekman/remind-bindings.el
;; Keywords: outlines
;; Package-Requires: ((emacs "26.1"))
;; Version: 0.1

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;;; Commentary:

;; Go through all and retrieve the top level definitions and their
;; positions then determine which functions are called by which others.


;;; Code:
(require 'package-map-secondhelp)
(require 'paren)

(defcustom package-map-parse-function-shapes
  '((setq . underline) (defvar . underline) (defcustom . plain) (defun . tab) (defsubst . component) (defmacro . trapezium))
  "Define variables to look, and the graphviz shapes they should take."
  :type 'list
  :group 'package-map)

(defcustom package-map-parse-subclustergroups
  '(:variables (setq defvar defcustom) :functions (defun defsubst defmacro))
  "Define subcluster groups and the which symbols should be assigned to them.  By default we only have variables and functions, though any number of groups can be defined. It is not necessary to use all symbols from `package-map-parse-function-shapes'.")

(defcustom package-map-parse-hashtablesize 50
  "Size of hash table.  50 by default."
  :type 'integer
  :group 'package-map)

(defun package-map-parse--getsourcefiles (&optional directory)
  "Find all source files from DIRECTORY, otherwise defer to `default-directory'."
  (let ((dir (or directory default-directory)))
    (--map (replace-regexp-in-string (format "^%s" dir) "" it)  ;; replace main directory
           (--filter (and (string-suffix-p ".el" it)            ;; don't want elc
                          (not (string-match-p "\\#" it)))      ;; don't want temp
                     (directory-files-recursively dir ".*\\.el")))))

;; ;; -- Not sure if this needs to be used. It could be useful for checking
;; ;;    import loops.
;; (defun package-map-parse--alltopdefs-file-requireprovide (file hashdefs)
;;   "Get all imports and package definitions from FILE and put into a HASHDEFS."
;;   (save-excursion
;;     (with-current-buffer (find-file-noselect file)
;;       (goto-char 0)
;;       (let ((provname nil)
;;             (mentions nil)
;;             (regit "^(\\(require\\|provide\\) '"))
;;         (while (search-forward-regexp regit nil t)
;;           ;; Get type
;;           (let* ((type-end (progn (forward-whitespace -1) (point)))
;;                  (type-beg (1+ (move-beginning-of-line 1)))
;;                  (type-nam (buffer-substring-no-properties type-beg type-end)))
;;             (goto-char type-end)
;;             (forward-whitespace 1)
;;             ;; Get variable name
;;             (let* ((req-beg (search-forward "'" (point-at-eol)))
;;                    (req-end (progn (forward-whitespace 1)
;;                                    (forward-whitespace -1)
;;                                    (search-backward ")" req-beg)))
;;                    (req-nam (buffer-substring-no-properties req-beg req-end)))
;;               ;; Make a wish make a succotash wish
;;               (cond ((string= type-nam "require") (push req-nam mentions))
;;                     ((string= type-nam "provide") (setq provname req-nam))
;;                     (t (error "Unknown: %s" type-nam))))))
;;         (if provname
;;             (puthash provname
;;                      `(:type "imports" :file ,file :mentions ,mentions)
;;                      hashdefs)
;;           (error "Unable to find provides for file %s" file))))))

(defun package-map-parse--alltopdefs-file (file hashdefs)
  "Get all top definitions in FILE and put into HASHDEFS.
Don't use `grep' or `projectile-ripgrep', because those sonuvabitch finish hooks are not reliable."
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (goto-char 0)
      (let ((reg-type (package-map-secondhelp--generateregexfromalist package-map-parse-function-shapes)))
        ;;(reg-vnam "\\(-*\\w+\\)+"))
        (while (search-forward-regexp reg-type nil t)
          ;; Get type
          (let* ((type-end (point))
                 (type-beg (1+ (move-beginning-of-line 1)))
                 (type-nam (buffer-substring-no-properties type-beg type-end)))
            (goto-char type-end)
            (forward-whitespace 1)
            ;; Get variable name
            (let* ((vnam-beg (point))
                   (vnam-end (progn (forward-whitespace 1) (forward-whitespace -1) (point)))
                   (vnam-nam (buffer-substring-no-properties vnam-beg vnam-end)))
              ;; Get bounds or line number
              (let ((lnum-beg (line-number-at-pos))
                    (lnum-end nil))
                (when (string= type-nam "defun")
                  (move-beginning-of-line 1)
                  (let* ((bounk (funcall show-paren-data-function))
                         (keybl (nth 3 bounk)))
                    (goto-char keybl)
                    (setq lnum-end (line-number-at-pos))))
                (puthash vnam-nam
                         `(:type ,type-nam
                                 :line-beg ,lnum-beg
                                 :line-end ,lnum-end
                                 :file ,file
                                 ;; when mentions is nil, somehow all entries in
                                 ;; the hash table point to the same mentions.
                                 :mentions (,vnam-nam))
                         hashdefs)))))
        hashdefs))))


(defun package-map-parse--alltopdefs-filelist (filelist)
  "Get all top definitions from FILELIST and return a hashtable, with variable names as keys as well as type and bounds as values."
  (let ((hashtable (make-hash-table
                    :size package-map-parse-hashtablesize
                    :test #'equal)))
    (dolist (pfile filelist hashtable)
      (package-map-parse--alltopdefs-file pfile hashtable))))
      ;;(package-map-parse--alltopdefs-file-requireprovide pfile hashtable)


(defun package-map-parse--allsecondarydefs-file (file hashtable)
  "Get all secondary definitions in FILE for each of the top level definitions in HASHTABLE."
  (let ((funcs-by-line-asc (package-map-secondhelp--makesortedlinelist
                            hashtable)))
    ;; -- Check each top def in the buffer
    (with-current-buffer (find-file-noselect file)
      (maphash   ;; iterate hashtable
       (lambda (vname annotations)
         (package-map-secondhelp--updatementionslist vname
                                                     file
                                                     annotations
                                                     funcs-by-line-asc))
       hashtable))))


(defun package-map-parse--allsecondarydefs-filelist (filelist hashtable)
  "Get all secondary definitions for all files in FILELIST for the top level definitions in HASHTABLE."
  (dolist (pfile filelist hashtable)
    (package-map-parse--allsecondarydefs-file pfile hashtable)))


(defun package-map-parse--generatemap ()
  "Generate a map of toplevel function and variable definitions in a project."
  (let* ((proj-files (package-map-parse--getsourcefiles))
         (hash-table (package-map-parse--alltopdefs-filelist proj-files)))
    (package-map-parse--allsecondarydefs-filelist proj-files hash-table)
    hash-table))

(provide 'package-map-parse)
;;; package-map-parse.el ends here
