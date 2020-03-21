;;; package-map.el --- Generate a graphviz map of functions and definitions -*- lexical-binding: t; -*-

;; Copright (C) 2020 Mehmet Tekman <mtekman89@gmail.com>

;; Author: Mehmet Tekman
;; URL: https://github.com/mtekman/remind-bindings.el
;; Keywords: outlines
;; Package-Requires: ((emacs "26.1") (projectile "2.2.0-snapshot"))
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

;; TODO: - Label (interactive) when parsing.

;;; Code:
(require 'package-map-parse)
(require 'org-table)
(require 'subr-x)

(defun package-map-makesummarytable ()
  "Make a summary org table of variables and references to them."
  (interactive)
  (let ((hashtable (package-map-parse--generatemap)))
    (with-current-buffer (find-file "graphviz2.org")
      (erase-buffer)
      (insert "| Type | Name | File | #Lines |\
 #Mentions | Mentions |\n|--\n")
      (maphash
       (lambda (funcname info)
         (let ((vfile (plist-get info :file))
               (vbegs (plist-get info :line-beg))
               (vends (plist-get info :line-end))
               (vtype (plist-get info :type))
               (vment (plist-get info :mentions)))
           (insert
            (format "| %s | %s | %s | %d | %d | %s |\n"
                    vtype funcname vfile
                    (if vends (- vends vbegs) 1)
                    (length vment)
                    vment))))
       hashtable)
      (org-table-align))))


(defvar package-map-colors-available
  '(red blue green orange purple gray yellow pink brown navy maroon violet))

(defun package-map--makecolormap (hashtable)
  "From the HASHTABLE make a color map of files."
  (let ((colors package-map-colors-available)
        (files-uniq (seq-uniq
                     (--map (plist-get it :file)
                            (hash-table-values
                             hashtable)))))
    (--map (let ((colr (nth it colors))
                 (file (nth it files-uniq)))
             `(,file . ,colr))
           (number-sequence 0 (1- (length files-uniq))))))

(defun package-map-makedotfile ()
  "Make a dot file representation of all the top level definitions in a project, and their references."
  (interactive)
  (let ((hashtable (package-map-parse--generatemap)))
    ;; TODO: implement these
    (let ((colormap (package-map--makecolormap hashtable))
          (shapemap package-map-parse-function-shapes))
      (with-current-buffer (find-file "graphviz2.dot")
        (erase-buffer)
        (insert "strict graph {\n")
        (maphash
         (lambda (funcname info)
           (let ((vfile (plist-get info :file))
                 (vbegs (plist-get info :line-beg))
                 (vends (plist-get info :line-end))
                 (vtype (plist-get info :type))
                 (vment (plist-get info :mentions)))
             (let ((numlines (if vends (- vends vbegs) 1)))
               (insert
                (format "  \"%s\" [height=%d,shape=%s,color=%s]\n"
                        funcname
                        (1+ (/ numlines 10))
                        (alist-get (intern vtype) shapemap)
                        (alist-get vfile colormap))))
             (dolist (mento vment)
               (unless (eq funcname mento)
                 (insert
                  (format "  \"%s\" -- \"%s\"\n"
                          funcname
                          mento))))))
         hashtable)
        (insert "}\n")))))



;; Logic:
;; -- if there is more than 1 file, then create several columns.
;; -- if only 1 file, more free for all approach.

;; [node]
;;  -- height (size of function), label (vname), color (file)
;; [edge]
;;  --


(provide 'package-map)
;;; package-map.el ends here
