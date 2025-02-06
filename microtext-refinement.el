;;; microtext-refinement.el --- A text refinement tool powered by gptel  -*- lexical-binding:t -*-

;; Copyright (C) 2025-present CHEN Xian'an (a.k.a `realazy').

;; Maintainer: xianan.chen@gmail.com
;; Package-Requires: ((gptel))
;; URL: https://github.com/cxa/microtext-refinement

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; See <https://www.gnu.org/licenses/> for GNU General Public License.

;;; Commentary:

;; 

;;; Code:

(require 'gptel)
(require 'smerge-mode)

(defgroup mtr nil
  "Refine the text using gptel."
  :prefix "mtr"
  :group 'editing)

(defcustom mtr-gptel-backend nil
  "Customize if you want to use a specific backend, default to `gptel-backend'. Please refer to https://github.com/karthink/gptel?tab=readme-ov-file#other-llm-backends."
  :group 'mtr)

(defcustom mtr-propmpt-role
  "Your task is to refine the given text for improved clarity, grammar, and style while preserving its original meaning."
  "Modify this role description to suit your specific requirements."
  :group 'mtr)

(defcustom mtr-explaination-lang "English"
  "In which language should the refinement be explained?"
  :group 'mtr)

(defvar mtr--prompt-output-guide
  (concat
   "Instructions:\n"
	 "1.	Refine the text: Improve readability, fix grammatical errors, and enhance overall coherence in its original language.\n"
	 "2.	Provide a structured output: Format your response using Markdown with a clear diff and explanation.Present the explanation in a bullet-point list format to ensure clarity and readability.\n"
	 "3.	Maintain fidelity: Ensure that the refined version stays true to the original intent.\n\n"

   "Output Format:\n\n"

   "## Diff\n\n"

   "<<<<<<< ORIGINAL\n"
   "Replace this line with the original passage\n"  
   "=======\n"  
   "Replace this line with the refined passage\n"  
   ">>>>>>> REFINED\n\n"  

   "## Explanation\n\n"

   "Replace this line with an explanation of the modifications, detailing grammar fixes, clarity improvements, and style enhancements.\n\n"))

(defun mtr--prompt-base ()
  "Base prompt."
  (concat mtr-propmpt-role "\n" mtr--prompt-output-guide))

(defun mtr--make-query (text)
  "Make a query for TEXT to refine."
  (concat
   "Regardless of the text’s original language, you must strictly provide the explanation in language: *" mtr-explaination-lang "*. If the explanation is not in *" mtr-explaination-lang "*, please translate it into *" mtr-explaination-lang "* before output.\n"
   "Read the provided text exactly as it is, without interpreting or altering its meaning before refinement. Pay special attention to the fact that any  marks or spaces at the beginning and end of the text are part of the text itself, not delimiters, and should be included exactly as they appear.\n"
   "Now, please refine the following text:\n\n"
   text))

(defconst mtr-buffer-name "*MicroText Refinement*")

(defun mtr--hide-conflict-marks ()
  "Hide conflict marks."
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward
            "\\(<<<<<<< .*\\|=======\\|>>>>>>> .*\\)\n" nil t)
      (let ((beg (match-beginning 0))
            (end (match-end 0)))
        (let ((ov (make-overlay beg end)))
          (overlay-put ov 'invisible t))))))

(defun mtr--explain (explanation)
  "Display EXPLANATION."
  (with-current-buffer mtr--buffer
    (setq buffer-read-only nil)
    (erase-buffer)
    (insert explanation)
    (markdown-mode)
    (smerge-mode +1)
    (goto-char (point-min))
    (when (re-search-forward "^=======\n" nil t)
      (goto-char (match-beginning 0))
      (smerge-refine))
    (mtr--hide-conflict-marks)
    (view-mode 1)
    (setq buffer-read-only t))
  (display-buffer mtr--buffer))

(defun mtr--smerge-lower-part ()
  "Get the content of the lower part in `smerge-mode`."
  (save-excursion
    (goto-char (point-min))
    (let ((beg (re-search-forward "^=======\n" nil t))
          (end (re-search-forward "^>>>>>>>\\(.*\\)\n" nil t))
          (end (1- (match-beginning 0))))
      (if (and beg end)
          (buffer-substring-no-properties beg end)
        (message "No conflict markers found.")))))

(defvar mtr--active-region nil)
(defvar mtr--buffer nil)

(defun mtr--handle-response (target-buffer response info)
  "Callback for `gptel-request'."
  (cond
   ((null response)
    (message "Failed to refine%s"
             (if-let ((msg (plist-get info :error)))
                 (format ", reason: %s" msg)
               "")))
   (t
    (mtr--explain response)
    (let ((refine-text
           (with-current-buffer mtr--buffer
             (mtr--smerge-lower-part)))
          (beg (car mtr--active-region))
          (end (cdr mtr--active-region)))
      (unless refine-text (user-error "Invalid response."))
      (with-current-buffer target-buffer
        (delete-region beg end)
        (goto-char beg)
        (insert refine-text)
        (pulse-momentary-highlight-region beg (point)))
      (with-current-buffer mtr--buffer
        (gptel--update-status " Refined" 'success))
      (message "Refined with %s"
               (gptel-backend-name (or mtr-gptel-backend gptel-backend)))))))

;;;###autoload
(defun mtr-refine (beg end)
  "Refine region."
  (interactive (if (region-active-p)
                   (list (region-beginning) (region-end))
                 (error "No text to refine, make a selection first.")))
  (setq mtr--active-region (cons beg end))
  (let ((gptel-backend (or mtr-gptel-backend gptel-backend)))
    (unless (buffer-live-p mtr--buffer)
      (setq mtr--buffer (gptel mtr-buffer-name)))
    (gptel--update-status " Waiting..." 'warning)
    (message "Refining with %s..." (gptel-backend-name gptel-backend))
    (gptel-request
        (mtr--make-query (buffer-substring-no-properties beg end))
      :system (mtr--prompt-base)
      :buffer mtr--buffer
      :callback (apply-partially #'mtr--handle-response (current-buffer)))))

(provide 'microtext-refinement)

;;; microtext-refinement.el ends here

