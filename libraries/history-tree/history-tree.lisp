;;;; SPDX-FileCopyrightText: Atlas Engineer LLC
;;;; SPDX-License-Identifier: BSD-3-Clause

(in-package :history-tree)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'node)
  (export '(parent children data)))
(defclass node ()
  ((parent :accessor parent
           :initarg :parent
           :initform nil)
   (children :accessor children
             :initarg :children
             :initform nil
             :documentation "List of nodes.")
   (data :accessor data
         :initarg :data
         :initform nil
         :documentation "Arbitrary data."))
  (:documentation "Internal node of the history tree."))

(defun make-node (&key data parent)
  (make-instance 'node :data data :parent parent))



(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'history-tree)
  (export '(root current)))
(defclass history-tree ()
  ((root :accessor root
         :initarg :root
         :type (or null node)
         :initform nil
         :documentation "The root node.
It only changes when deleted.")
   (current :accessor current
            :type (or null node)
            :initform nil
            :documentation "The current node.
It changes every time a node is added or deleted."))
  (:documentation "History tree data structure."))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'make))
(defun make ()
  (make-instance 'history-tree))



(deftype positive-integer ()
  `(integer 1 ,most-positive-fixnum))

(deftype non-negative-integer ()
  `(integer 0 ,most-positive-fixnum))



(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'back))
;; TODO: Can we set ftype for methods return value?
;; (declaim (ftype (function (history-tree &optional positive-integer))
;;                 back))
(defmethod back ((history history-tree) &optional (count 1))
  "Go COUNT parent up from the current node.
Return (VALUES HISTORY (CURRENT HISTORY)) so that `back' and `forward' calls can
be chained."
  (when (and (current history)
             (parent (current history)))
    ;; Put former current node back in first position if it is not already
    ;; there, e.g. if current node was set manually.
    (let ((former-current (current history)))
      (setf (current history) (parent (current history)))
      (setf (children (current history))
            (cons former-current
                  (delete former-current (children (current history))))))
    (when (< 1 count)
      (back history (1- count))))
  (values history (current history)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'forward))
;; (declaim (ftype (function (history-tree &optional positive-integer))
;;                 forward))
(defmethod forward ((history history-tree) &optional (count 1))
  "Go COUNT first-children down from the current node.
Return (VALUES HISTORY (CURRENT HISTORY)) so that `back', `forward', and
`go-to-child' calls can be chained."
  (when (and (current history)
             (children (current history)))
    (setf (current history) (first (children (current history))))
    (when (< 1 count)
      (forward history (1- count)))))



(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'go-to-child))
(defmethod go-to-child (data (history history-tree) &key (test #'equal))
  "Go to direct current node's child matching DATA.
Test is done with the TEST argument.
Return (VALUES HISTORY (CURRENT HISTORY)) so that `back', `forward', and
`go-to-child' calls can be chained."
  (when (current history)
    (let ((selected-child))
      (setf (children (current history))
            (delete-if (lambda (node)
                         (when (funcall test (data node) data)
                           (setf selected-child node)))
                       (children (current history))))
      (when selected-child
        (push selected-child (children (current history)))
        (forward history))))
  (values history (current history)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'delete-child))
(defmethod delete-child (data (history history-tree) &key (test #'equal))
  "Delete child matching DATA and return the child.
Test is done with the TEST argument."
  (when (current history)
    (let ((matching-node nil))
      (setf (children (current history))
            (delete-if (lambda (node)
                         (when (funcall test (data node) data)
                           (setf matching-node node)))
                       (children (current history))))
      matching-node)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'add-child))
(defmethod add-child (data (history history-tree) &key (test #'equal))
  "Create a node for DATA and add it to the list of children in first position.

No node is created if data is in current node or already among the children, but
the existing node data is updated to DATA (the TEST function does not
necessarily mean the data is identical).

If there is no current element, this creates the first element of the tree.

Child is moved first in the list if it already exists.

Current node is then updated to the first child if it holds DATA."
  (cond
    ((null (current history))
     (let ((new-node (make-node :data data)))
        (setf (root history) new-node)
        (setf (current history) (root history))
       new-node))
    ((not (funcall test data (data (current history))))
     (let ((node (delete-child data history :test test)))
       (push (or (when node
                   (setf (data node) data)
                   node)
                 (make-node :data data :parent (current history)))
              (children (current history)))
        (forward history)
       (current history)))
    (t
     (setf (data (current history)) data)
     (current history))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'map-tree))
(defun map-tree (function tree &key flatten include-root (collect-function #'cons))
  "Map the FUNCTION over the TREE.
If TREE is a `htree:history-tree', start from it's root.
If TREE is a `htree:node', start from it.
Include results of applying FUNCTION over ROOT if INCLUDE-ROOT is
non-nil.
Return results as cons cells tree if FLATTEN is nil and as a flat
list otherwise.
COLLECT-FUNCTION is the function of two arguments that glues the
current node to the result of further traversal."
  (labels ((collect (node children)
             (funcall collect-function node children))
           (traverse (node)
             (when node
               (collect (funcall function node)
                 ;; This lambda here because (apply #'identity ...) fails on empty arglist.
                 (apply (if flatten #'append #'(lambda (&rest args) args))
                        (mapcar #'traverse (children node)))))))
    (let ((root (typecase tree
                  (htree:node tree)
                  (htree:history-tree (htree:root tree)))))
      (when root
        (if include-root
            (traverse root)
            (apply #'append (mapcar #'traverse (children root))))))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'do-tree))
(defmacro do-tree ((var tree) &body body)
  "Apply actions in BODY to all the nodes in a tree.
Nodes are bound to VAR.
If TREE is a node, if's passed right away,
if it is a tree, then the root is taken.

Always return nil, as it is an explicitly imperative macro."
  `(progn
     (map-tree (lambda (,var) ,@body) ,tree :include-root t)
     ;; Explicitly return nil
     nil))


(defmethod all-children ((node node))
  (map-tree #'identity node :flatten t))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'all-nodes))
(defmethod all-nodes ((history history-tree))
  "Return a list of all nodes, in depth-first order."
  (let ((root (root history)))
    (when root (cons root (all-children root)))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'parent-nodes))
(defmethod parent-nodes ((history history-tree))
  "Return a list of all parents of the current node.
First parent comes first in the resulting list."
  (loop for node = (current history) then (parent node)
        when (and node (parent node))
          collect (parent node)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'forward-children-nodes))
(defmethod forward-children-nodes ((history history-tree))
  "Return a list of the first children, recursively.
First child comes first in the resulting list."
  (loop for node = (current history) then (first (children node))
        when (and node (children node))
          collect (first (children node))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'children-nodes))
(defmethod children-nodes ((history history-tree))
  "Return a list of all the children of the current node.
The nodes come in depth-first order."
  (and (current history)
       (all-children (current history))))



(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'all-nodes-data))
(defmethod all-nodes-data ((history history-tree))
  "Return a list of all nodes data, in depth-first order."
  (mapcar #'data (all-nodes history)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'parent-nodes-data))
(defmethod parent-nodes-data ((history history-tree))
  "Return a list of all nodes data.
First parent comes first."
  (mapcar #'data (parent-nodes history)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'forward-children-nodes-data))
(defmethod forward-children-nodes-data ((history history-tree))
  "Return a list of all forward children nodes data.
First child comes first."
  (mapcar #'data (forward-children-nodes history)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'children-nodes-data))
(defmethod children-nodes-data ((history history-tree))
  "Return a list of all children nodes data, in depth-first order."
  (mapcar #'data (children-nodes history)))


(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'find-data))
(defmethod find-data (data (history history-tree) &key (test #'equal) ensure-p)
  "Find a tree node matching DATA in HISTORY and return it.
If ENSURE-P is non-nil, create this node when not found.
Search is done with the help of TEST argument."
  (let ((match (block search
                 (do-tree (node history)
                   (when (funcall test data (data node))
                                 (return-from search node))))))
    (or match (when ensure-p (add-child data history :test test)))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'delete-node))
(defmethod delete-node (data (history history-tree) &key (test #'equal) rebind-children-p)
  "Delete node matching DATA from HISTORY and return the node.
If the node has children itself, and REBIND-CHILDREN-P is not nil, these
will become children of the node's parent. Search is done with the
help of TEST argument."
  ;; TODO: This (block ... (map-tree ... (return-from ...))) repeats. Abstract it?
  (block delete
    (do-tree (node history)
      (when (funcall test data (data node))
                    (setf (children (parent node))
                          (append (when rebind-children-p (children node))
                                  (remove node (children (parent node)))))
                    (return-from delete node)))))


(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'depth))
;; (declaim (ftype (function (history-tree) non-negative-integer)
;;                 depth))
(defmethod depth ((history history-tree))
  "Return the number of parents of the current node."
  (length (parent-nodes history)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'size))
;; (declaim (ftype (function (history-tree) non-negative-integer)
;;                 size))
(defmethod size ((history history-tree))
  "Return the number of nodes."
  ;; TODO: This could be optimized with a SIZE slot, but is it worth it?
  (length (all-nodes history)))
