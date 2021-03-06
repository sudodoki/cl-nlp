;;; (c) 2014-2017 Vsevolod Dyomkin

(in-package #:nlp.parsing)
(named-readtables:in-readtable rutilsx-readtable)

(declaim (inline read-stanford-dep read-conll-dep print-stanford-dep))


(defstruct (dep (:print-object print-stanford-dep))
  (rel nil :type (or symbol null))
  (head nil :type (or token null))
  (child nil :type (or token null)))

(defgeneric print-dep (format dep &optional stream)
  (:documentation
   "FORMAT may be :stanford, :conll, and, maybe some other.")
  (:method ((format (eql :stanford)) dep &optional (stream *standard-output*))
      (format stream "~(~A~)(~A-~A, ~A-~A)"
              @dep.rel @dep.head.word @dep.head.id @dep.child.word @dep.child.id))
  (:method ((format (eql :conll)) dep &optional (stream *standard-output*))
    (format stream "~A	~A	~:[_~;~:*~A~]	_	~A	~A~%"
            @dep.child.id @dep.child.word @dep.child.lemma @dep.child.pos
            @dep.head.id @dep.rel)))

(defun print-stanford-dep (dep stream)
  "Print DEP in Stanford dependency format to STREAM."
  (print-dep :stanford dep stream))

(defun read-stanford-dep (str &optional (tokens #h(0 +root+)))
  "Read one Stanford format dependency from STR.
   TOKENS is a cache of already encountered tokens."
  (let* ((split1 (position #\( str))
         (split2 (position #\, str))
         (split3 (position #\) str))
         (head (split #\- (string-trim +white-chars+
                                       (slice str (1+ split1) split2))))
         (head-idx (parse-integer (second head)))
         (child (split #\- (string-trim +white-chars+
                                       (slice str (1+ split2) (1- split3)))))
         (child-idx (parse-integer (second child))))
    (make-dep :rel (mksym (slice str 0 split1) :package :deps)
              :head (getset# head-idx tokens
                             (make-token :id head-idx :word (first head)))
              :child (getset# child-idx tokens
                              (make-token :id child-idx :word (first child))))))

(defun read-conll-dep (str &optional (tokens #h(0 +root+)))
  "Read one CONLL format dependency from STR.
   TOKENS is a cache of already encountered tokens."
  (ds-bind (id word lemma pos pos2 feats head-id rel &rest rest)
      (split #\Tab str :remove-empty-subseqs t)
    (declare (ignore pos2 feats rest))
    (let ((child-id (parse-integer id))
          (head-id (parse-integer head-id)))
      (make-dep :rel (mksym rel :package :dep)
                :head (or (? tokens head-id)
                          (make-token :id head-id))
                :child (getset# child-id tokens
                                (make-token :id child-id
                                            :word word
                                            :lemma (unless (string= "_" lemma)
                                                     lemma)
                                            :pos (mksym pos :package :tag)))))))

(defgeneric read-deps (format str)
  (:documentation
   "Read a dependency parse sturcture in a given FORMAT from STR.
    Returns a list of list of dependencies for each sentence.")
  (:method (format (str string))
    (with-input-from-string (in str)
      (call-next-method format in)))
  (:method ((format (eql :stanford)) (str stream))
    (let (tokens all-deps deps)
      (loop :for line := (read-line str nil) :while line :do
         (if (blankp line)
             (progn
               (:= tokens #h(0 +root+))
               (when deps (push (reverse deps) all-deps))
               (void deps))
             (push (read-stanford-dep line tokens) deps)))
      (reverse all-deps)))
  (:method ((format (eql :conll)) (str stream))
    (let ((tokens #h(0 +root+))
          all-deps deps)
      (loop :for line := (read-line str nil) :while line :do
         (if (blankp line)
             (progn
               (when deps
                 (dolist (dep deps)
                   (:= (dep-head dep)
                       (? tokens (token-id (dep-head dep)))))
                 (push (reverse deps) all-deps))
               (:= tokens #h(0 +root+))
               (void deps))
             (push (read-conll-dep line tokens) deps)))
      (reverse all-deps))))

(defun deps->tree (deps &optional dep)
  (when deps
    (unless dep (:= dep (find 'dep:root deps :key 'dep-rel)))
    (cons dep
          (sort (cons @dep.child
                      (mapcar ^(deps->tree deps %)
                              (keep-if ^(eql @dep.child %) deps
                                       :key 'dep-head)))
                '< :key #`(token-id (etypecase %
                                      (token %)
                                      (list @%.child#0)))))))

#+nil
(defun pprint-deps-tree (deps)
  (let ((*package* (find-package :dep)))
    (pprint-tree (maptree #`(etypecase %
                              (dep (dep-rel %))
                              (token (token-word %)))
                          (deps->tree deps)))))
