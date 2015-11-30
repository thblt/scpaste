;;; scpaste.el --- Paste to the web via scp.

;; Copyright © 2008-2012 Phil Hagelberg and contributors

;; Author: Phil Hagelberg
;; URL: https://github.com/technomancy/scpaste
;; Version: 0.6.4
;; Created: 2008-04-02
;; Keywords: convenience hypermedia
;; EmacsWiki: SCPaste
;; Package-Requires: ((htmlize "1.39"))

;; This file is NOT part of GNU Emacs.

;;; Commentary:

;; This will place an HTML copy of a buffer on the web on a server
;; that the user has shell access on.

;; It's similar in purpose to services such as http://paste.lisp.org
;; or http://rafb.net, but it's much simpler since it assumes the user
;; has an account on a publicly-accessible HTTP server. It uses `scp'
;; as its transport and uses Emacs' font-lock as its syntax
;; highlighter instead of relying on a third-party syntax highlighter
;; for which individual language support must be added one-by-one.

;;; Install

;; Add Marmalade as a package source, and then run M-x package-install
;; scpaste.

;; Set `scpaste-http-destination' and `scpaste-scp-destination' to
;; appropriate values, and add this to your Emacs config:

;; (setq scpaste-http-destination "http://p.hagelb.org"
;;       scpaste-scp-destination "p.hagelb.org:p.hagelb.org")

;; If you have a different keyfile, you can set that, too:
;; (setq scpaste-scp-pubkey "~/.ssh/my_keyfile.pub")

;; If you use a non-standard ssh port, you can specify it by setting
;; `scpaste-scp-port'.

;; Optionally you can set the displayed name for the footer and where
;; it should link to:
;; (setq scpaste-user-name "Technomancy"
;;       scpaste-user-address "http://technomancy.us/")

;;; Usage

;; M-x scpaste, enter a name, and press return. The name will be
;; incorporated into the URL by escaping it and adding it to the end
;; of `scpaste-http-destination'. The URL for the pasted file will be
;; pushed onto the kill ring.

;; You can autogenerate a splash page that gets uploaded as index.html
;; in `scpaste-http-destination' by invoking M-x scpaste-index. This
;; will upload an explanation as well as a listing of existing
;; pastes. If a paste's filename includes "private" it will be skipped.

;; You probably want to set up SSH keys for your destination to avoid
;; having to enter your password once for each paste. Also be sure the
;; key of the host referenced in `scpaste-scp-destination' is in your
;; known hosts file--scpaste will not prompt you to add it but will
;; simply hang.

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Code:

(require 'url)
(require 'htmlize)

(defvar scpaste-scp-port
  nil)

(defvar scpaste-http-destination
  "http://p.hagelb.org"
  "Publicly-accessible (via HTTP) location for pasted files.")

(defvar scpaste-scp-destination
  "p.hagelb.org:p.hagelb.org"
  "SSH-accessible directory corresponding to `scpaste-http-destination'.
You must have write-access to this directory via `scp'.")

(defvar scpaste-scp-pubkey
  nil
  "Identity file for the server, corresponds to ssh’s `-i` option
Example: \"~/.ssh/id.pub\"")

(defvar scpaste-user-name
  nil
  "Name displayed under the paste.")

(defvar scpaste-user-address
  nil
  "Link to the user’s homebase (can be a mailto:).")


;; To set defvar while developing: (load-file (buffer-file-name))
(defvar scpaste-el-location load-file-name)

(defun scpaste-footer ()
  "HTML message to place at the bottom of each file."
  (concat "<p style='font-size: 8pt; font-family: monospace;'>Generated by "
          (let ((user (or scpaste-user-name user-full-name)))
            ;;(concat "DEBUG" user scpaste-user-name scpaste-user-address)
            (if scpaste-user-address
                (concat "<a href='" scpaste-user-address "'>" user "</a>")
                user))
          " using <a href='http://p.hagelb.org'>scpaste</a> at %s. "
          (cadr (current-time-zone)) ". (<a href='%s'>original</a>)</p>"))


;;;###autoload
(defun scpaste (original-name)
  "Paste the current buffer via `scp' to `scpaste-http-destination'."
  (interactive "MName (defaults to buffer name): ")
  (let* ((b (htmlize-buffer))
         (name (url-hexify-string (if (equal "" original-name)
                                      (buffer-name)
                                    original-name)))
         (full-url (concat scpaste-http-destination "/" (url-hexify-string name)
                           ".html"))
         (scp-destination (concat scpaste-scp-destination "/" name ".html"))
         (scp-original-destination (concat scpaste-scp-destination "/" name))
         (tmp-file (concat temporary-file-directory name)))

    ;; Save the file (while adding footer)
    (save-excursion
      (switch-to-buffer b)
      (goto-char (point-min))
      (search-forward "</body>\n</html>")
      (insert (format (scpaste-footer)
                      (current-time-string)
                      (substring full-url 0 -5)))
      (write-file tmp-file)
      (kill-buffer b))

    (let* ((identity (if scpaste-scp-pubkey
                         (concat "-i " scpaste-scp-pubkey)
                       ""))
           (port (if scpaste-scp-port (concat "-P " scpaste-scp-port)))
           (invocation (concat "scp -q " identity " " port))
           (command-1 (concat invocation
                              " " tmp-file
                              " " scp-destination)))

      (let* ((error-buffer "*scp-error*")
               (retval (with-temp-message (format "Executing %s" command-1)
                         (shell-command command-1 nil error-buffer)))
               (x-select-enable-primary t))
        (delete-file tmp-file)
          ;; Notify user and put the URL on the kill ring
          (if (= retval 0)
              (progn (kill-new full-url)
                     (message "Pasted to %s (on kill ring)" full-url))
            (progn
              (pop-to-buffer error-buffer)
              (help-mode-setup)))))))

;;;###autoload
(defun scpaste-region (name)
  "Paste the current region via `scpaste'."
  (interactive "MName: ")
  (let ((region-contents (buffer-substring (mark) (point))))
    (with-temp-buffer
      (insert region-contents)
      (scpaste name))))

;;;###autoload
(defun scpaste-index ()
  "Generate an index of all existing pastes on server on the splash page."
  (interactive)
  (let* ((dest-parts (split-string scpaste-scp-destination ":"))
         (files (shell-command-to-string (concat "ssh " (car dest-parts)
                                                 " ls " (cadr dest-parts))))
         (file-list (split-string files "\n")))
    (save-excursion
      (with-temp-buffer
        (insert-file-contents scpaste-el-location)
        (goto-char (point-min))
        (search-forward ";;; Commentary")
        (forward-line -1)
        (insert "\n;;; Pasted Files\n\n")
        (dolist (file file-list)
          (when (and (string-match "\\.html$" file)
                     (not (string-match "private" file)))
            (insert (concat ";; * <" scpaste-http-destination "/" file ">\n"))))
        (emacs-lisp-mode) (font-lock-fontify-buffer) (rename-buffer "SCPaste")
        (write-file "/tmp/scpaste-index")
        (scpaste "index")))))

(provide 'scpaste)
;;; scpaste.el ends here
