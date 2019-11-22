(defmacro xenops-define-apply-command (op-type docstring)
  `(defun ,(intern (concat "xenops-" (symbol-name op-type))) ()
     ,(concat docstring " "
              "The elements operated on are determined by trying the following:
1. The element at point, if any.
2. Elements in the active region, if there is an active region.
3. All elements in the buffer.")
     (interactive)
     (xenops-apply ',op-type)))

(defmacro xenops-define-apply-at-point-command (op-type docstring)
  `(defun ,(intern (concat "xenops-" (symbol-name op-type) "-at-point")) ()
     ,docstring
     (interactive)
     (-when-let (el (xenops-apply-parse-at-point))
       (-when-let (op (xenops-element-op-of-type-for-el el ',op-type))
         (funcall op el)))))

(defun xenops-apply (op-type &optional pred)
  "Apply operation type OP-TYPE to any elements encountered. The region
operated on is either the element at point, the active region, or
the entire buffer.

Optional argument PRED is a function taking an element plist as
its only argument. The element will be operated on iff PRED
returns non-nil."
  (xenops-apply-operations (xenops-ops-for-op-type op-type) pred))

(defun xenops-apply-operations (ops &optional pred)
  "Apply operations OPS to any elements encountered. The region
operated on is either the element at point, the active region, or
the entire buffer."
  (cl-flet ((process (lambda (el)
                       (-if-let (op (xenops-element-op-for-el el ops))
                           (save-excursion (funcall op el))))))
    (-if-let (el (xenops-apply-parse-at-point))
        (process el)
      (destructuring-bind (beg end region-active)
          (if (region-active-p)
              `(,(region-beginning) ,(region-end) t)
            `(,(point-min) ,(point-max) nil))
        (save-excursion
          (goto-char beg)
          (let (el)
            (while (setq el (xenops-apply-get-next-element end))
              (if (and (xenops-element-element? el)
                       (or (null pred) (funcall pred el)))
                  (process el)))))
        ;; Hack: This should be abstracted.
        (and region-active (not (-intersection ops '(xenops-math-image-increase-size
                                                     xenops-math-image-decrease-size)))
             (deactivate-mark))))))

(defun xenops-apply-get-next-element (end)
  "If there is another element, return it and leave point after it.
An element is a plist containing data about a regexp match for a
section of the buffer that xenops can do something to."
  (cl-flet ((next-match-pos (regexp)
                            (save-excursion
                              (if (re-search-forward regexp end t) (match-beginning 0) end))))
    (let ((element (-min-by (lambda (delims1 delims2)
                              (> (next-match-pos (car (plist-get delims1 :delimiters)))
                                 (next-match-pos (car (plist-get delims2 :delimiters)))))
                            (xenops-apply-get-all-delimiters))))
      (when (re-search-forward (car (plist-get element :delimiters)) end t)
        (let* ((type (plist-get element :type))
               (parse-match (xenops-elements-get type :parse-match))
               (element (funcall parse-match element)))
          (and element (goto-char (plist-get element :end)))
          (or element 'unparseable))))))

(defun xenops-apply-get-all-delimiters ()
  (cl-flet ((get-delimiters (type)
                            (mapcar (lambda (delimiters)
                                      `(:type ,type :delimiters ,delimiters))
                                    (xenops-elements-get type :delimiters))))
    (apply #'append (mapcar #'get-delimiters (mapcar #'car xenops-elements)))))

(defun xenops-apply-parse-at-point ()
  (xenops-util-first-result #'funcall (xenops-elements-get-all :parse-at-point)))

(provide 'xenops-apply)