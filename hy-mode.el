;;; hy-mode.el --- Major mode for Hylang -*- lexical-binding: t -*-

;; Copyright © 2013 Julien Danjou <julien@danjou.info>
;;           © 2017 Eric Kaschalk <ekaschalk@gmail.com>
;;
;; Authors: Julien Danjou <julien@danjou.info>
;;          Eric Kaschalk <ekaschalk@gmail.com>
;; URL: http://github.com/hylang/hy-mode
;; Version: 1.0
;; Keywords: languages, lisp, python
;; Package-Requires: ((dash "2.13.0") (dash-functional "1.2.0") (s "1.11.0") (emacs "24"))

;; hy-mode is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; hy-mode is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with hy-mode.  If not, see <http://www.gnu.org/licenses/>.

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Provides font-lock, indentation, navigation, autocompletion, eldoc, and more
;; for the Hy language. (http://hylang.org)

;;; Code:

(require 'cl)
(require 'dash)
(require 'dash-functional)
(require 's)

(defgroup hy-mode nil
  "A mode for Hy"
  :prefix "hy-mode-"
  :group 'applications)


;;; Configuration

(defconst hy-shell-interpreter "hy"
  "Default Hy interpreter name.")


(defvar hy-shell-interpreter-args "--spy"
  "Default arguments for Hy interpreter.")


(defvar hy-font-lock-highlight-percent-args? t
  "Whether to highlight '%i' symbols in Hy's clojure-like syntax for lambdas.")


(defvar hy-indent-special-forms
  '(:exact
    ("when" "unless"
     "for" "for*" "for/a" "for/a*"
     "while"
     "except" "catch"
     "->" "->>")

    :fuzzy
    ("def"
     "with"
     "let"
     "with/a"
     "fn"
     "fn/a"
     "lambda"))
  "Special forms to always indent following line by +1.

Fuzzy forms require match at start of symbol (eg. with-something)
will indent special. Exact forms require the symbol and def exactly match.")


;;; Syntax Tables

(defconst hy-mode-syntax-table
  (-let [table
         (copy-syntax-table lisp-mode-syntax-table)]
    (modify-syntax-entry ?\{ "(}" table)
    (modify-syntax-entry ?\} "){" table)
    (modify-syntax-entry ?\[ "(]" table)
    (modify-syntax-entry ?\] ")[" table)

    ;; Quote characters are prefixes
    (modify-syntax-entry ?\~ "'" table)
    (modify-syntax-entry ?\@ "'" table)

    ;; "," is a symbol in Hy, namely the tuple constructor
    (modify-syntax-entry ?\, "_ p" table)

    ;; "|" is a symbol in hy, naming the or operator
    (modify-syntax-entry ?\| "_ p" table)

    ;; "#" is a tag macro, we include # in the symbol
    (modify-syntax-entry ?\# "_ p" table)

    table)
  "Hy mode's syntax table.")


(defconst inferior-hy-mode-syntax-table
  (copy-syntax-table hy-mode-syntax-table)
  "Inferior Hy mode's syntax tables inherits Hy mode's table.")


;;; Keywords

(defconst hy--kwds-anaphorics
  '("ap-if" "ap-each" "ap-each-while" "ap-map" "ap-map-when" "ap-filter"
    "ap-reject" "ap-dotimes" "ap-first" "ap-last" "ap-reduce" "ap-pipe"
    "ap-compose" "xi")

  "Hy anaphoric contrib keywords.")


(defconst hy--kwds-builtins
  '("*map" "accumulate" "and" "assoc" "butlast" "calling-module-name" "car"
    "cdr" "chain" "coll?" "combinations" "comp" "complement" "compress" "cons"
    "cons?" "constantly" "count" "cut" "cycle" "dec" "defmain" "del"
    "dfor" "disassemble" "distinct" "doto" "drop" "drop-last" "drop-while"
    "empty?" "even?" "every?" "filter" "first" "flatten" "float?" "fraction"
    "genexpr" "gensym" "get" "group-by" "identity" "inc" "input"
    "instance?" "integer" "integer-char?" "integer?" "interleave" "interpose"
    "is" "is-not" "is_not" "islice" "iterable?" "iterate" "iterator?" "juxt"
    "keyword" "keyword?" "last" "list*" "lfor" "macroexpand"
    "macroexpand-1" "map" "merge-with" "multicombinations" "name" "neg?" "none?"
    "nth" "numeric?" "odd?" "or" "partition" "permutations"
    "pos?" "product" "quasiquote" "quote" "range" "read" "read-str"
    "reduce" "remove" "repeat" "repeatedly" "rest" "second" "setv" "sfor"
    "slice" "some" "string" "string?" "symbol?" "take" "take-nth" "take-while"
    "tee" "unquote" "unquote-splice" "xor" "zero?" "zip" "zip-longest"

    ;; Pure python builtins
    "abs" "all" "any" "bin" "bool" "callable" "chr"
    "compile" "complex" "delattr" "dict" "dir" "divmod" "enumerate"
    "eval" "float" "format" "frozenset" "getattr" "globals" "hasattr"
    "hash" "help" "hex" "id" "isinstance" "issubclass" "iter" "len"
    "list" "locals" "max" "memoryview" "min" "next" "object" "oct" "open"
    "ord" "pow" "repr" "reversed" "round" "set" "setattr"
    "sorted" "str" "sum" "super" "tuple" "type" "vars"
    "ascii" "bytearray" "bytes" "exec"
    "--package--" "__package__" "--import--" "__import__"
    "--all--" "__all__" "--doc--" "__doc__" "--name--" "__name__")

  "Hy builtin keywords.")


(defconst hy--kwds-constants
  '("True" "False" "None"
    "Ellipsis"
    "NotImplemented"
    "nil"  ; For those that alias None as nil
    )

  "Hy constant keywords.")


(defconst hy--kwds-exceptions
  '("ArithmeticError" "AssertionError" "AttributeError" "BaseException"
    "DeprecationWarning" "EOFError" "EnvironmentError" "Exception"
    "FloatingPointError" "FutureWarning" "GeneratorExit" "IOError"
    "ImportError" "ImportWarning" "IndexError" "KeyError"
    "KeyboardInterrupt" "LookupError" "MemoryError" "NameError"
    "NotImplementedError" "OSError" "OverflowError"
    "PendingDeprecationWarning" "ReferenceError" "RuntimeError"
    "RuntimeWarning" "StopIteration" "SyntaxError" "SyntaxWarning"
    "SystemError" "SystemExit" "TypeError" "UnboundLocalError"
    "UnicodeDecodeError" "UnicodeEncodeError" "UnicodeError"
    "UnicodeTranslateError" "UnicodeWarning" "UserWarning" "VMSError"
    "ValueError" "Warning" "WindowsError" "ZeroDivisionError"
    "BufferError" "BytesWarning" "IndentationError" "ResourceWarning" "TabError")

  "Hy exception keywords.")


(defconst hy--kwds-defs
  '("defn" "defn/a"
    "defmacro" "defmacro/g!" "defmacro!"
    "deftag" "defmain" "defmulti"
    "defmethod")

  "Hy definition keywords.")


(defconst hy--kwds-operators
  '("!=" "%" "%=" "&" "&=" "*" "**" "**=" "*=" "+" "+=" "," "-"
    "-=" "/" "//" "//=" "/=" "<" "<<" "<<=" "<=" "=" ">" ">=" ">>" ">>="
    "^" "^=" "|" "|=" "~")

  "Hy operator keywords.")


(defconst hy--kwds-special-forms
  '(;; Looping
    "loop" "recur"
    "for" "for*" "for/a" "for/a*"

    ;; Threading
    "->" "->>" "as->"
    "some->" "some->>"

    ;; Flow control
    "return"
    "if" "if*" "if-not" "lif" "lif-not"
    "else" "unless" "when"
    "break" "continue"
    "while" "cond"
    "do" "progn"

    ;; Functional
    "fn" "fn/a"
    "await"
    "yield" "yield-from"
    "with" "with*" "with/a" "with/a*"
    "with-gensyms"

    ;; Error Handling
    "except" "try" "throw" "raise" "catch" "finally" "assert"

    ;; Special
    "print"
    "not"
    "in" "not-in"

    ;; Misc
    "global" "nonlocal"
    "eval" "eval-and-compile" "eval-when-compile")

  "Hy special forms keywords.")


;;; Font Locks
;;;; Definitions

(defconst hy--font-lock-kwds-builtins
  (list
   (rx-to-string
    `(: symbol-start
        (or ,@hy--kwds-operators
            ,@hy--kwds-builtins
            ,@hy--kwds-anaphorics)
        symbol-end))

   '(0 font-lock-builtin-face))

  "Hy builtin keywords.")


(defconst hy--font-lock-kwds-constants
  (list
   (rx-to-string
    `(: symbol-start
        (or ,@hy--kwds-constants)
        symbol-end))

   '(0 font-lock-constant-face))

  "Hy constant keywords.")


(defconst hy--font-lock-kwds-defs
  (list
   (rx-to-string
    `(: "("
        symbol-start
        (group-n 1 (or ,@hy--kwds-defs))
        (1+ space)
        (group-n 2 (1+ word))))

   '(1 font-lock-keyword-face)
   '(2 font-lock-function-name-face nil t))

  "Hy definition keywords.")


(defconst hy--font-lock-kwds-exceptions
  (list
   (rx-to-string
    `(: symbol-start
        (or ,@hy--kwds-exceptions)
        symbol-end))

   '(0 font-lock-type-face))

  "Hy exception keywords.")


(defconst hy--font-lock-kwds-special-forms
  (list
   (rx-to-string
    `(: symbol-start
        (or ,@hy--kwds-special-forms)
        symbol-end))

   '(0 font-lock-keyword-face))

  "Hy special forms keywords.")

;;;; Static

(defconst hy--font-lock-kwds-class
  (list
   (rx (group-n 1 "defclass")
       (1+ space)
       (group-n 2 (1+ word)))

   '(1 font-lock-keyword-face)
   '(2 font-lock-type-face))

  "Hy class keywords.")


(defconst hy--font-lock-kwds-decorators
  (list
   (rx
    (or (: "#@"
           (syntax open-parenthesis))
        (: symbol-start
           "with-decorator"
           symbol-end
           (1+ space)))
    (1+ word))

   '(0 font-lock-type-face))

  "Hylight the symbol after `#@' or `with-decorator' macros.")


(defconst hy--font-lock-kwds-imports
  (list
   (rx symbol-start
       (or "import" "require" ":as")
       symbol-end)

   '(0 font-lock-keyword-face))

  "Hy import keywords.")


(defconst hy--font-lock-kwds-self
  (list
   (rx symbol-start
       (group "self")
       (or "." symbol-end))

   '(1 font-lock-keyword-face))

  "Hy self keyword.")


(defconst hy--font-lock-kwds-tag-macros
  (list
   (rx "#"
       (not (any "*" "@" "[" ")" space))  ; #* is unpacking, #@ decorator, #[ bracket str
       (0+ (syntax word)))

   '(0 font-lock-function-name-face))

  "Hylight tag macros, ie. `#tag-macro', so they stand out.")

;;;; Misc

(defconst hy--font-lock-kwds-anonymous-funcs
  (list
   (rx symbol-start
       (group "%" (1+ digit))
       (or "." symbol-end))

   '(1 font-lock-variable-name-face))

  "Hy '#%(print %1 %2)' styling anonymous variables.")


(defconst hy--font-lock-kwds-func-modifiers
  (list
   (rx symbol-start "&" (1+ word))

   '(0 font-lock-type-face))

  "Hy '&rest/&kwonly/...' styling.")


(defconst hy--font-lock-kwds-kwargs
  (list
   (rx symbol-start ":" (1+ word))

   '(0 font-lock-constant-face))

  "Hy ':kwarg' styling.")


(defconst hy--font-lock-kwds-shebang
  (list
   (rx buffer-start "#!" (0+ not-newline) eol)

   '(0 font-lock-comment-face))

  "Hy shebang line.")


(defconst hy--font-lock-kwds-unpacking
  (list
   (rx (or "#*" "#**")
       symbol-end)

   '(0 font-lock-keyword-face))

  "Hy #* arg and #** kwarg unpacking keywords.")

(defconst hy--font-lock-kwds-variables
  (list
   (rx symbol-start
       "setv"
       symbol-end
       (1+ space)
       (group (1+ word)))

   '(1 font-lock-variable-name-face))

  "Hylight variable names in setv/def, only first name.")

;;;; Advanced Keywords

(defconst hy--tag-comment-prefix-rgx
  (rx "#_" (* " ") (group-n 1 (not (any " "))))
  "The regex to match #_ tag comment prefixes.")

(defun hy--search-comment-macro (limit)
  "Search for a comment forward stopping at LIMIT."
  (-when-let* ((_ (re-search-forward hy--tag-comment-prefix-rgx limit t))
               (md (match-data))
               (start (match-beginning 1))
               (state (syntax-ppss start)))
    (if (hy--in-string-or-comment? state)
        (hy--search-comment-macro limit)
      (goto-char start)
      (forward-sexp)
      (setf (elt md 3) (point))
      (set-match-data md)
      t)))

(defconst hy--font-lock-kwds-tag-comment-prefix
  (list 'hy--search-comment-macro

        '(1 font-lock-comment-face t))
  "Support for higlighting #_(form) the form as a comment.")

;;;; Grouped

(defconst hy-font-lock-kwds
  (list hy--font-lock-kwds-builtins
        hy--font-lock-kwds-class
        hy--font-lock-kwds-constants
        hy--font-lock-kwds-defs
        hy--font-lock-kwds-decorators
        hy--font-lock-kwds-exceptions
        hy--font-lock-kwds-func-modifiers
        hy--font-lock-kwds-imports
        hy--font-lock-kwds-kwargs
        hy--font-lock-kwds-self
        hy--font-lock-kwds-shebang
        hy--font-lock-kwds-special-forms
        hy--font-lock-kwds-tag-macros
        hy--font-lock-kwds-unpacking
        hy--font-lock-kwds-variables

        ;; Advanced kwds
        hy--font-lock-kwds-tag-comment-prefix

        ;; Optional kwds
        (when hy-font-lock-highlight-percent-args?
          hy--font-lock-kwds-anonymous-funcs))
  "All Hy font lock keywords.")


;;; Utilities
;;;; Syntax States
;;;;; Aliases

(defun hy--sexp-innermost-char (state)
  (nth 1 state))
(defun hy--start-of-last-sexp (state)
  (nth 2 state))
(defun hy--in-string? (state)
  (nth 3 state))
(defun hy--in-string-or-comment? (state)
  (or (nth 3 state) (nth 4 state)))
(defun hy--start-of-string (state)
  (nth 8 state))

;;;;; Navigation

(defun hy--prior-sexp? (state)
  (number-or-marker-p (hy--start-of-last-sexp state)))


(defun hy--goto-innermost-char ()
  "Try to goto the innermost character of form containing point."
  (-some-> (syntax-ppss) hy--sexp-innermost-char goto-char))


(defun hy--at-a-form-opener (state)
  ;; TODO in the middle of defn isnt working
  (and (not (hy--prior-sexp? (syntax-ppss)))
       (not (hy--start-of-string (syntax-ppss)))))

;;;; Form Extraction

(defun hy--current-form-string ()
  "Get form containing current point as string plus a trailing newline."
  (save-excursion
    (-when-let* ((state (syntax-ppss))
                 (start-pos (hy--sexp-innermost-char state)))
      (goto-char start-pos)
      (while (ignore-errors (forward-sexp)))
      (buffer-substring-no-properties start-pos (point)))))


(defun hy--parent-defun-string ()
  "Get the defun containing current point as string."
  (save-excursion
    (let ((found
           (and (s-equals? (thing-at-point 'symbol) "defn")
                (hy--at-a-form-opener (syntax-ppss))))
          (start-pos
           (point)))

      ;; Only the first previous form-opener defun need be considered
      ;; Since any further defuns couldn't possibly contain start-pos
      (while (and (not found)
                  (re-search-backward (rx symbol-start "defn" symbol-end) nil t))
        (setq found (hy--at-a-form-opener (syntax-ppss))))

      (-when-let* ((state
                    (and found (syntax-ppss)))
                   (lower-bound
                    (hy--sexp-innermost-char state))
                   (upper-bound
                    (scan-lists lower-bound 1 0))
                   (_ (> upper-bound start-pos)))
        (buffer-substring-no-properties lower-bound upper-bound)))))


(defun hy--current-region-string ()
  "Get the currently selected contiguous region as a string."
  (when (and (region-active-p)
             (not (region-noncontiguous-p)))
    (buffer-substring (region-beginning) (region-end))))


(defun hy--last-sexp-string ()
  "Get form containing last s-exp point as string plus a trailing newline."
  (save-excursion
    (-when-let* ((state (syntax-ppss))
                 (start-pos (hy--start-of-last-sexp state)))
      (goto-char start-pos)
      (while (ignore-errors (forward-sexp)))

      (concat (buffer-substring-no-properties start-pos (point)) "\n"))))

;;;; General purpose

(defun hy--str-or-nil (text)
  "If TEXT is non-blank, return TEXT else nil."
  (and (not (s-blank? text)) text))


(defun hy--str-or-empty (text)
  "Return TEXT or the empty string if TEXT is nil."
  (if text text ""))


;;; Indentation
;;;; Utilities

(defun hy--anything-before? (pos)
  "Determine if chars before POS in current line."
  (s-matches? (rx (not blank))
              (buffer-substring (line-beginning-position) pos)))


(defun hy--anything-after? (pos)
  "Determine if POS is before line-end-position."
  (and pos (< pos (line-end-position))))


(defun hy--check-non-symbol-sexp (pos)
  "Check for a non-symbol yet symbol-like (tuple constructor comma) at POS."
  (and (member (char-after pos) '(?\, ?\|))
       (char-equal (char-after (1+ pos)) ?\s)))

;;;; Normal Indent

(defun hy--normal-indent (last-sexp)
  "Determine normal indentation column of LAST-SEXP.

Example:
 (a (b c d
       e
       f))

1. Indent e => start at d -> c -> b.
Then backwards-sexp will throw error trying to jump to a.
Observe 'a' need not be on the same line as the ( will cause a match.
Then we determine indentation based on whether there is an arg or not.

2. Indenting f will go to e.
Now since there is a prior sexp d but we have no sexps-before on same line,
the loop will terminate without error and the prior lines indentation is it."
  (goto-char last-sexp)
  (-let [last-sexp-start nil]
    (if (ignore-errors
          (while (hy--anything-before? (point))
            (setq last-sexp-start
                  (let* ((at-prefix-char?
                          (-contains? '(?\' ?\` ?\~ ?\#) (char-before)))

                         (at-unquote-splice?
                          (and (eq ?\@ (char-before))
                               (save-excursion
                                 (forward-char -1)
                                 (eq ?\~ (char-before)))))

                         (offset
                          (cond (at-prefix-char? 1)
                                (at-unquote-splice? 2)
                                (t 0))))

                    (prog1 (- (point) offset) (backward-sexp)))))
          t)
        (current-column)
      (if (not (hy--anything-after? last-sexp-start))
          (1+ (current-column))
        (goto-char last-sexp-start)  ; Align with function argument
        (current-column)))))

;;;; Function or form

(defun hy--not-function-form? ()
  "Non-nil if form at point doesn't represent a function call."
  (or (-contains? '(?\[ ?\{) (char-after))
      (not (looking-at (rx anything  ; Skips form opener
                           (or (syntax symbol) (syntax word)))))))


(defun hy--function-form? ()
  "Alias the complement of `hy--not-function-form?'"
  (not (hy--not-function-form?)))

;;;; Hy find indent spec

(defun hy--find-indent-spec (state)
  "Return integer for special indentation of form or nil to use normal indent.

Note that `hy--not-function-form?' filters out forms that are lists and dicts.
Point is always at the start of a function."
  (-when-let (function (and (hy--prior-sexp? state)
                            (thing-at-point 'symbol)))
    (-let [(&plist :exact exact :fuzzy fuzzy)
           hy-indent-special-forms]
      (or (-contains? exact function)
          (-some (-cut s-matches? <> function) fuzzy)))))

;;;; Hy indent function

(defun hy-indent-at-outline? ()
  "If `indent-point' is a line containing an outline, indent at left margin."
  (save-excursion
    (goto-char (line-beginning-position))
    (re-search-forward
     (rx (group (0+ space)) ";; " (1+ "*") space)
     (line-end-position) t)))


(defun hy-indent-function (indent-point state)
  "Indent at INDENT-POINT where STATE is `parse-partial-sexp' for INDENT-POINT."
  (goto-char (hy--sexp-innermost-char state))

  (if (hy--not-function-form?)
      (1+ (current-column))  ; Indent after [, {, ... is always 1
    (forward-char 1)  ; Move to start of sexp

    (cond ((hy--check-non-symbol-sexp (point))  ; Comma tuple constructor
           (+ 2 (current-column)))

          ((hy--find-indent-spec state)  ; Special form uses fixed indendation
           (1+ (current-column)))

          (t
           (hy--normal-indent calculate-lisp-indent-last-sexp)))))


(defun hy-indent-line ()
  "Perform `lisp-indent-line' with check for `outline' headers."
  (if (hy-indent-at-outline?)
      (progn (line-beginning-position) (replace-match "" nil nil nil 1))
    (lisp-indent-line)))


;;; Bracket String Literals

(defun hy--match-bracket-string (limit)
  "Search forward for a bracket string literal."
  (re-search-forward
   (rx "#["
       (0+ not-newline)
       "["
       (group (1+ (not (any "]"))))
       "]"
       (0+ not-newline)
       "]")
   limit
   t))


(defun hy-syntax-propertize-function (start end)
  "Implements context sensitive syntax highlighting beyond `font-lock-keywords'.

In particular this implements bracket string literals.
START and END are the limits with which to search for bracket strings passed
and determined by `font-lock-mode' internals when making an edit to a buffer."
  (save-excursion
    (goto-char start)

    (-when-let* ((state
                  (syntax-ppss))
                 (inner-char
                  (hy--sexp-innermost-char state))
                 (offset
                  (length "#["))
                 (fixed-start
                  (- inner-char offset)))
      (goto-char fixed-start))

    (while (hy--match-bracket-string end)
      (put-text-property (1- (match-beginning 1)) (match-beginning 1)
                         'syntax-table (string-to-syntax "|"))

      (put-text-property (match-end 1) (1+ (match-end 1))
                         'syntax-table (string-to-syntax "|")))))


;;; Font Lock Syntactics

(defun hy--string-in-doc-position? (state)
  "Is STATE within a docstring?"
  (if (= 1 (hy--start-of-string state))  ; Identify module docstring
      t
    (-when-let* ((first-sexp (hy--sexp-innermost-char state))
                 (function (save-excursion
                             (goto-char (1+ first-sexp))
                             (thing-at-point 'symbol))))
      (and (s-matches? (rx "def" (not blank)) function)
           (not (s-matches? (rx "defmethod") function))))))


(defun hy-font-lock-syntactic-face-function (state)
  "Return syntactic face function for the position represented by STATE.
STATE is a `parse-partial-sexp' state, and the returned function is the
Lisp font lock syntactic face function. String is shorthand for either
a string or comment."
  (if (hy--in-string? state)
      (if (hy--string-in-doc-position? state)
          font-lock-doc-face
        font-lock-string-face)
    font-lock-comment-face))


;;; Shell
;;;; Configuration
;;;;; Buffers

(defconst hy-shell-buffer-name "Hy"
  "Default buffer name for Hy interpreter.")


(defconst hy-shell-internal-buffer-name "Hy Internal"
  "Default buffer name for the internal Hy process.")


(defvar hy-shell-buffer nil
  "The current shell buffer for Hy.")


(defvar hy-shell-internal-buffer nil
  "The current internal shell buffer for Hy.")

;;;;; Internal Process Code

(defvar hy-shell-internal-setup-code
  "(import [jedhy.api [API :as --API]]) (setv api (--API))"
  "Setup `jedhy' for internal process.")


(defvar hy-shell-internal-update-namespace-code
  "(.set-namespace api :globals- (globals) :locals- (locals))"
  "Update the namespace used by `jedhy' to current namespace.")

;;;;; Comint

(defvar hy-shell-prompt-regexp "^=>+ *"
  "Hy shell's value for `comint-prompt-regexp'.")


(defvar hy--shell-output-filter-in-progress nil
  "Whether we are waiting for output from `hy--shell-send-string'.")


(defvar hy--shell-output-filter-string nil
  "The iteratively concatenated output from `hy--shell-send-string'.")


(defvar hy--shell-font-lock-enable t
  "Whether the shell should font-lock the current line.")

;;;; Shell buffer and process management
;;;;; Utilities

(defun hy-installed? ()
  "Is the `hy-shell-interpreter' command available?"
  (when (executable-find hy-shell-interpreter) t))


(defmacro hy--when-installed (&rest forms)
  "Execute FORMS if `hy-installed?' otherwise message not installed."
  `(if (not (hy-installed?))
       (message "Hy not found. Activate a virtual environment with Hy.")
     ,@forms))


(defun hy-buffer (&optional name internal)
  "Get the `hy-shell-(internal)-buffer-(name)'."
  (cond ((and name internal)
         hy-shell-internal-buffer-name)
        ((and name (not internal))
         hy-shell-buffer-name)
        (internal
         hy-shell-internal-buffer)
        (t
         hy-shell-buffer)))

;;;;; Process Management

(defun hy--shell-format-process-name (proc-name)
  "Format a PROC-NAME with closing astericks."
  (->> proc-name (s-prepend "*") (s-append "*")))

(defun hy-shell-get-process-name (&optional internal)
  "Get process name corr. to `hy-shell-buffer-name'/`hy-shell-internal-buffer-name'."
  (if internal
      hy-shell-internal-buffer-name
    hy-shell-buffer-name))

(defun hy-shell-get-process (&optional internal)
  "Get process corr. to `hy-shell-buffer-name'/`hy-shell-internal-buffer-name'."
  (-> (hy-buffer 'name internal)
     hy--shell-format-process-name
     get-buffer-process))


(defun hy-shell-internal-process? ()
  "Is the internal hy shell process live and return it, simple alias function."
  (hy-shell-get-process 'internal))


(defun hy--shell-current-buffer-process ()
  "Get process associated with current buffer."
  (get-buffer-process (current-buffer)))


(defun hy--shell-current-buffer-a-process? ()
  "Is `current-buffer' a live process?"
  (process-live-p (hy--shell-current-buffer-process)))

;;;;; Buffer Management

(defun hy--shell-get-or-create-buffer ()
  "Get or create `hy-shell-buffer' buffer for current hy shell process."
  (if hy-shell-buffer
      hy-shell-buffer
    (hy--shell-with-shell-buffer
     (-let [proc-name
            (process-name (hy--shell-current-buffer-process))]
       (generate-new-buffer proc-name)))))


(defun hy--shell-buffer? (&optional internal)
  "Is `hy-shell-buffer'/`hy-shell-internal-buffer' set and does it exist?"
  (-when-let (buffer
              (hy-buffer nil internal))
    (buffer-live-p buffer)))


(defun hy--shell-kill-buffer (&optional internal)
  "Kill either `hy-shell-buffer'/`hy-shell-internal-buffer' process."
  (-when-let (buffer
              (hy-buffer nil internal))
    (kill-buffer buffer)
    (when (derived-mode-p 'inferior-hy-mode)
      (setf buffer nil))))


(defun hy-shell-kill ()
  "Kill both `hy-shell-buffer'/`hy-shell-internal-buffer' hy processes."
  (hy--shell-kill-buffer)
  (hy--shell-kill-buffer 'internal))

;;;; Shell macros

(defmacro hy--shell-with-shell-buffer (&rest forms)
  "Execute FORMS in the shell buffer."
  (-let [shell-process
         (gensym)]
    `(-let [,shell-process
            (hy-shell-get-process)]
       (with-current-buffer (process-buffer ,shell-process)
         ,@forms))))


(defmacro hy--shell-with-font-locked-shell-buffer (&rest forms)
  "Execute FORMS in the shell buffer with font-lock turned on."
  `(hy--shell-with-shell-buffer
    (save-current-buffer
      (unless (hy--shell-buffer?)
        (setq hy-shell-buffer (hy--shell-get-or-create-buffer)))
      (set-buffer hy-shell-buffer)

      (unless (font-lock-mode) (font-lock-mode 1))
      (unless (derived-mode-p 'hy-mode) (hy-mode))

      ,@forms)))

;;;; Font locking
;;;;; Prompt Input

(defun hy--shell-faces-to-font-lock-faces (text &optional start-pos)
  "Set all 'face in TEXT to 'font-lock-face optionally starting at START-POS."
  (let ((pos 0)
        (start-pos (or start-pos 0)))
    (while (and (/= pos (length text))
                (setq next (next-single-property-change pos 'face text)))
      (-let* ((plist (text-properties-at pos text))
              ((&plist 'face face) plist))
        (set-text-properties (+ start-pos pos) (+ start-pos next)
                             (-doto plist
                               (plist-put 'face nil)
                               (plist-put 'font-lock-face face)))
        (setq pos next)))))


(defun hy--shell-fontify-prompt-post-command-hook ()
  "Fontify just the current line in `hy-shell-buffer' for `post-command-hook'.

Constantly extracts current prompt text and executes and manages applying
`hy--shell-faces-to-font-lock-faces' to the text."
  (-when-let* (((_ . prompt-end)
                comint-last-prompt)
               (_ (and prompt-end
                       (> (point) prompt-end)  ; new command is being entered
                       (hy--shell-current-buffer-a-process?))))  ; process alive?
      (let* ((input (buffer-substring-no-properties prompt-end (point-max)))
             (deactivate-mark nil)
             (buffer-undo-list t)
             (font-lock-buffer-pos nil)
             (text (hy--shell-with-font-locked-shell-buffer
                    (delete-region (line-beginning-position) (point-max))
                    (setq font-lock-buffer-pos (point))
                    (insert input)
                    (font-lock-ensure)
                    (buffer-substring font-lock-buffer-pos (point-max)))))
        (hy--shell-faces-to-font-lock-faces text prompt-end))))


(defun hy--shell-font-lock-turn-on ()
  "Turn on fontification of current line for hy shell."
  (hy--shell-with-shell-buffer
   (hy--shell-kill-buffer)

   ;; Required - I don't understand why killing doesn't capture the end nil setq
   (setq-local hy-shell-buffer nil)

   (add-hook 'post-command-hook
             'hy--shell-fontify-prompt-post-command-hook nil 'local)
   (add-hook 'kill-buffer-hook
             'hy--shell-kill-buffer nil 'local)))

;;;; Send strings

(defun hy--shell-end-of-output? (string)
  "Return non-nil if STRING ends with the prompt."
  (s-matches? comint-prompt-regexp string))


(defun hy--shell-output-filter (string)
  "If STRING ends with input prompt then set filter in progress done."
  (when (hy--shell-end-of-output? string)
    (setq hy--shell-output-filter-in-progress nil))
  "\n=> ")


(defun hy--shell-send-string (string &optional process internal)
  "Internal implementation of shell send string functionality."
  (-let ((process (or process
                      (hy-shell-get-process internal)))
         (hy--shell-output-filter-in-progress t))
    (unless process
      (error "No active Hy process found/given!"))
    (comint-send-string process string)
    (when (or (not (string-match "\n\\'" string))
              (string-match "\n[ \t].*\n?\\'" string))
      (comint-send-string process "\n"))))


(defun hy-shell-send-string-no-output (string &optional process internal)
  "Send STRING to hy PROCESS and inhibit printing output."
  (let* ((comint-preoutput-filter-functions
          '(hy--shell-output-filter))
         (process (or process (hy-shell-get-process internal)))
         (hy--shell-output-filter-in-progress t)
         (inhibit-quit t))
    (unless process
      (error "No active Hy process found/given!"))
    (or (with-local-quit
          (hy--shell-send-string string process internal)
          (while hy--shell-output-filter-in-progress
            (accept-process-output process))
          t)
        (with-current-buffer (process-buffer process)
          (comint-interrupt-subjob)))))


(defun hy-shell-send-string-internal (string)
  "Send STRING to internal hy shell process."
  (hy-shell-send-string-no-output string nil 'internal))


(defun hy-shell-send-string (string &optional process)
  "Send STRING to hy PROCESS."
  (-let [comint-output-filter-functions
         '(hy--shell-output-filter)]
    (hy--shell-send-string string process)))

(defun hy--shell-chomp-async-output (text)
  "Chomp prefixes and suffixes from async internal process output."
  (->> text
     (s-chop-suffixes '("\n=> " "=> " "\n"))
     (s-chop-prefixes '("\"" "'" "\"'" "'\""))
     (s-chop-suffixes '("\"" "'" "\"'" "'\""))))


(defun hy--shell-send-async (string)
  "Send STRING to internal hy process asynchronously."
  (let ((output-buffer
         (get-buffer-create " *Comint Hy Redirect Work Buffer*"))
        (proc
         (hy-shell-internal-process?)))
    (if proc
        (with-current-buffer output-buffer
          (erase-buffer)
          (comint-redirect-send-command-to-process string output-buffer proc nil t)

          (set-buffer hy-shell-internal-buffer)
          (while (and (null comint-redirect-completed)
                      (accept-process-output proc nil 100 t)))
          (set-buffer output-buffer)

          (hy--shell-chomp-async-output (buffer-string)))
      (message "Hy internal process is not running."))))

;;;; Update internal process

(defconst hy--import-rgx
  (rx "(" (0+ space)
      (or "import" "require" "sys.path.extend"))
  "A *temporary* regex used to extract import forms for updating IDE features.")


(defun hy--shell-update-imports ()
  "Send imports/requires to the current internal process and updating namespace.

This is currently done manually as I'm not sure of the consequences of doing
so automatically through eg. regular intervals. Sending the imports allows
Eldoc/Company to function on packages like numpy/pandas, even if done via an
alias like (import [numpy :as np]).

Right now the keybinding is not publically exposed while I decide on a way
to continue."
  (interactive)
  (save-excursion
    (goto-char (point-min))

    (while (re-search-forward hy--import-rgx nil t)
      (hy-shell-send-string-internal (hy--current-form-string)))

    (hy-shell-send-string-internal hy-shell-internal-update-namespace-code)))

;;;; Shell creation

(defun hy--shell-calculate-command (&optional internal)
  "Calculate the string used to execute the inferior Hy process."
  (format "%s %s"
          (shell-quote-argument hy-shell-interpreter)
          (if internal
              ""
            hy-shell-interpreter-args)))


(defun hy--shell-make-comint (cmd proc-name &optional show internal)
  "Create and return comint process PROC-NAME with CMD, opt. INTERNAL and SHOW."
  (-when-let* ((proc-buffer-name
                (hy--shell-format-process-name proc-name))
               (_
                (not (comint-check-proc proc-buffer-name)))
               (cmdlist
                (split-string-and-unquote cmd))
               (buffer
                (apply 'make-comint-in-buffer proc-name proc-buffer-name
                       (car cmdlist) nil (cdr cmdlist)))
               (process
                (get-buffer-process buffer)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'inferior-hy-mode)
        (inferior-hy-mode)))
    (when show
      (display-buffer buffer))
    (if internal
        (progn
          (set-process-query-on-exit-flag process nil)
          (setq hy-shell-internal-buffer buffer))
      (setq hy-shell-buffer buffer))
    proc-buffer-name))

;;;; Run Shell

(defun run-hy-internal ()
  "Start an inferior hy process in the background for autocompletion."
  (interactive)
  (unless (hy-installed?)
    (message "Hy not found, activate a virtual environment containing Hy to use
Eldoc, Anaconda, and other hy-mode features."))

  (when (and (not (hy-shell-get-process 'internal))
             (hy-installed?))
    (-let [hy--shell-font-lock-enable
           nil]
      (prog1
          (-> (hy--shell-calculate-command 'internal)
              (hy--shell-make-comint (hy-shell-get-process-name 'internal) nil 'internal)
             get-buffer-process)
        (hy--shell-send-internal-setup-code)
        (message "Hy internal process successfully started")))))


(defun hy--restart-hy-internal ()
  "Perform `run-hy-internal', killing the current internal process if present."
  (interactive)
  (hy--shell-kill-buffer 'internal)
  (run-hy-internal))


(defun run-hy (&optional cmd)
  "Run an inferior Hy process, CMD defaulting to `hy--shell-calculate-command'."
  (interactive)
  (hy--when-installed
   (unless (hy-shell-get-process)
     (let ((cmd (or cmd (hy--shell-calculate-command)))
           (buffer (hy-buffer 'name)))
       (hy--shell-make-comint cmd buffer 'show)))))


;;; Jedhy
;;;; Constants

(defconst hy--jedhy-completions-rgx
  (rx "'"
      (group (1+ (not (any ",)"))))
      "'"
      (any "," ")"))

  "Regex to extra candidates from `jedhy'")

;;;; Commands

(defun hy--jedhy-format-cmd (candidate command-type)
  "Format jedhy cmd for CANDIDATE and COMMAND-TYPE.

It can be one of: 'annotation, 'completion, or 'eldoc."
;;  (format "(.%s api \"%s\")"
;;          (pcase command-type
;;            ('annotation "annotate")
;;            ('completion "complete")
;;            ('eldoc      "docs"))
;;          candidate)
)


(defun hy--jedhy-send (candidate command-type)
  "Send CANDIDATE to process for COMMAND-TYPE, see `hy--jedhy-format-cmd'."
  (-some-> candidate (hy--jedhy-format-cmd command-type) hy--shell-send-async))

;;;; Specializations

(defun hy--eldoc-documentation-function-internal (candidate)
  "Perform `eldoc-documentation-function' duties for extracted CANDIDATE."
  (-some->
   candidate
   (hy--jedhy-send 'eldoc)
   hy--str-or-nil
   hy--eldoc-fontify-text))

;;;; Symbol Extraction

(defun hy--candidate-is-method? (candidate)
  "Is CANDIDATE a method call (eg. .append in (.append some-list 1))."
  (s-starts-with? "." candidate))


(defun hy--get-next-symbol ()
  "Extract next symbol after point for completing methods."
  (ignore-errors (forward-sexp) (forward-char) t)
  (pcase (char-after)
    ;; Can't send just .method to eldoc, next symbol not entered yet
    ((or ?\) ?\s ?\C-j) nil)

    ;; Dot dsl doesn't work on literals, substitute the types
    (?\[ "list")
    (?\{ "dict")
    (?\" "str")

    ;; Otherwise complete the dot dsl
    (_ (progn (forward-char) (thing-at-point 'symbol)))))


(defun hy--get-inner-symbol ()
  "Traverse and inspect innermost sexp and return formatted string for eldoc."
  (save-excursion
    (-when-let (function
                (and (hy--goto-innermost-char)
                     (hy--function-form?)
                     (progn (forward-char) (thing-at-point 'symbol))))

      ;; Attribute method call (eg. ".format str") needs following sexp
      (if (hy--candidate-is-method? function)
          (concat (hy--get-next-symbol) function)
        function))))


;;; Eldoc
;;;; Fontification

(defun hy--fontify-text (text regexp &rest faces)
  "Fontify portions of TEXT matching REGEXP with FACES."
  (when text
    (-each
        (s-matched-positions-all regexp text)
      (-lambda ((beg . end))
        (--each faces
          (add-face-text-property beg end it nil text))))))


(defun hy--eldoc-fontify-text (text)
  "Fontify eldoc TEXT."
  (let ((kwd-rx
         (rx string-start (1+ (not (any space ":"))) ":"))
        (kwargs-rx
         (rx symbol-start "&" (1+ word)))
        (arg-kwarg-rx
         (rx (or "#*" "#**")))
        (quoted-args-rx
         (rx "`" (1+ (not space)) "`")))
    (hy--fontify-text text kwd-rx         'font-lock-keyword-face)
    (hy--fontify-text text kwargs-rx      'font-lock-type-face)
    (hy--fontify-text text arg-kwarg-rx 'font-lock-keyword-face)
    (hy--fontify-text text quoted-args-rx 'font-lock-constant-face 'bold-italic))
  text)

;;;; Documentation Function

(defun hy-eldoc-documentation-function ()
  "Exract and send Hy candidate for fontified eldoc string."
  (when (hy-shell-internal-process?)
    (hy--eldoc-documentation-function-internal (hy--get-inner-symbol))))


;;; Documentation Lookup

(defun hy--docs-for-thing-at-point ()
  "Mirrors `hy-eldoc-documentation-function' formatted for a buffer, not a msg."
  ;; TODO Old style S-K doc lookups formatting not implemented in updated
  ;; jedhy package. Currently maintaining this with eldoc-style formatting
  ;; while I finalize integration of basic jedhy features
  (hy-eldoc-documentation-function))


(defun hy--format-docs-for-buffer (text)
  "Format raw hydoc TEXT for inserting into hyconda buffer."
  (-let [kwarg-newline-regexp
         (rx ","
             (1+ (not (any "," ")")))
             (group-n 1 "\\\n")
             (1+ (not (any "," ")"))))]
    (-some--> text
            (s-replace "\\n" "\n" it)
            (replace-regexp-in-string kwarg-newline-regexp
                                      "newline" it nil t 1))))


(defun hy-describe-thing-at-point ()
  "Implement shift-k docs lookup for `spacemacs/evil-smart-doc-lookup'."
  (interactive)
  (-when-let* ((text (hy--docs-for-thing-at-point))
               (doc-buffer "*Hyconda*"))
    (with-current-buffer (get-buffer-create doc-buffer)
      (erase-buffer)
      (switch-to-buffer-other-window doc-buffer)

      (insert text)
      (goto-char (point-min))
      (forward-line)

      (insert "------\n")
      (fill-region (point) (point-max))

      ;; Eventually make hyconda-view-minor-mode, atm this is sufficient
      (local-set-key "q" 'quit-window)
      (when (fboundp 'evil-local-set-key)
        (evil-local-set-key 'normal "q" 'quit-window)))))


;;; Company
;;;; Candidate methods


(defun hy--company-eldoc (candidate)
  "Get company meta, the eldoc, for CANDIDATE."
  (-> candidate hy--eldoc-documentation-function-internal hy--str-or-empty))


(defun hy--company-complete (candidate)
  "Get company completion candidates for CANDIDATE."
  (-when-let (candidates (and (not (hy--candidate-is-method? candidate))
                              (hy--jedhy-send candidate 'completion)))
    (-some->>
     candidates
     (s-match-strings-all hy--jedhy-completions-rgx)
     (-select-column 1))))   ; Extract the rgx's group matches


(defun hy--company-annotate (candidate)
  "Get company annotation for CANDIDATE."
  (-some-> candidate (hy--jedhy-send 'annotation) hy--str-or-empty))

;;;; Driver

(defun company-hy (command &optional candidate &rest ignored)
  (interactive (list 'interactive))
  (cl-case command
    (prefix
     (company-grab-symbol))
    (candidates
     (hy--company-complete candidate))
    (annotation
     (hy--company-annotate candidate))
    (meta
     (hy--company-eldoc candidate))))


;;; EXPERIMENTAL JEDHY INSTALLATION COMMANDS
;; ;;;; Commands

;; (defconst hy--jedhy-uninstall-cmd
;;   "(import pip) (pip.main [\"uninstall\" \"jedhy\" \"-yes\"])"
;;   "Command to uninstall Jedhy.")


;; ;; NOTE MOVE this to hy-personal and set to nil here
;; (defconst hy--jedhy-dev-dir "/home/ekaschalk/dev/jedhy"
;;   "Path to local development version of `jedhy' for 'pip install -e'.")


;; (defun hy--jedhy-format-install-dev-mode-cmd ()
;;   "Format the installation command for dev-mode versions of `jedhy'."
;;   (unless hy--jedhy-dev-dir
;;     (message "Must set `hy--jedhy-dev-dir' for dev mode."))

;;   ;; NOTE
;;   ;; 1. HAVE TO RESTART THE SHELL AFTERWARDS
;;   ;; 2. HAVE TO DO (import jedhy.actions) not (import jedhy)
;;   (format "(import pip) (pip.main [\"install\" \"-e\" %s])"
;;           hy--jedhy-dev-dir))

;; ;;;; Execution

;; (defun hy-uninstall-jedhy ()
;;   "Uninstall jedhy?"
;;   (interactive)
;;   (when (y-or-n-p "Uninstall Jedhy?")
;;     (hy--shell-send-async hy--jedhy-uninstall-cmd)))


;; (defun hy-install-jedhy-dev-mode ()
;;   "Install editable jedhy in `hy--jedhy-dev-dir'.?"
;;   (interactive)
;;   (when (y-or-n-p "Install *dev-version* of Jedhy?")
;;     (hy--shell-send-async (hy--jedhy-format-install-dev-mode-cmd))
;;     ;; message if successful
;;     ;; message if failed
;;     ;; message if already present
;;     ;; message if should reinstall jedhy
;;     ))


;;; Keybindings
;;;; Utilities

(defun hy-define-keys (keymap &rest pairs)
  "Define alternating key-def PAIRS for KEYMAP."
  (-each
      (-partition 2 pairs)
    (-lambda ((key def))
      (define-key keymap key def))))


(defun hy-shell-eval (text &optional echo)
  "Send TEXT to shell, starting up if needed, and possibly ECHOing."
  (when text
    (unless (hy--shell-buffer?)
      (hy-shell-start-or-switch-to-shell))

    (hy--shell-with-shell-buffer
     (if echo
         (hy-shell-send-string text)
       (hy-shell-send-string-no-output text)))))

;;;; Functions

;;;###autoload
(defun hy-insert-pdb ()
  "Import and set pdb trace at point."
  (interactive)
  (insert "(do (import pdb) (pdb.set-trace))"))


;;;###autoload
(defun hy-insert-pdb-threaded ()
  "Import and set pdb trace at point for a threading macro."
  (interactive)
  (insert "((fn [x] (import pdb) (pdb.set-trace) x))"))


;;;###autoload
(defun hy-shell-start-or-switch-to-shell ()
  (interactive)
  (if (and (hy--shell-buffer?) (get-buffer-process hy-shell-buffer))
      (switch-to-buffer-other-window
       (hy--shell-get-or-create-buffer))
    (run-hy)))


;;;###autoload
(defun hy-shell-eval-buffer ()
  "Send the buffer to the shell, inhibiting output."
  (interactive)
  (hy-shell-eval (buffer-string)))


;;;###autoload
(defun hy-shell-eval-region ()
  "Send highlighted region to shell, inhibiting output."
  (interactive)
  (hy-shell-eval (hy--current-region-string)))


;;;###autoload
(defun hy-shell-eval-current-form ()
  "Send form containing current point to shell."
  (interactive)
  (hy-shell-eval (hy--current-form-string) 'echo))


;;;###autoload
(defun hy-shell-eval-last-sexp ()
  "Send form containing the last s-expression to shell."
  (interactive)
  (hy-shell-eval (hy--last-sexp-string) 'echo))


;;;###autoload
(defun hy-shell-eval-defun ()
  (interactive)
  (hy-shell-eval (hy--parent-defun-string)))


;;; hy-mode and inferior-hy-mode
;;;; Hy-mode setup

(defun hy--mode-setup-eldoc ()
  (make-local-variable 'eldoc-documentation-function)
  (setq-local eldoc-documentation-function 'hy-eldoc-documentation-function)
  (eldoc-mode +1))


(defun hy--mode-setup-font-lock ()
  (setq-local font-lock-multiline t)
  (setq font-lock-defaults
        '(hy-font-lock-kwds
          nil nil
          (("+-*/.<>=!?$%_&~^:@" . "w"))  ; syntax alist
          nil
          (font-lock-mark-block-function . mark-defun)
          (font-lock-syntactic-face-function  ; Differentiates (doc)strings
           . hy-font-lock-syntactic-face-function))))


(defun hy--mode-setup-internal-process ()
  (setenv "PYTHONIOENCODING" "UTF-8")

  ;; Startup Hy internal process
  (run-hy-internal)
  (add-hook 'pyvenv-post-activate-hooks 'run-hy-internal nil t))


(defun hy--mode-setup-syntax ()
  ;; Bracket string literals require context sensitive highlighting
  (setq-local syntax-propertize-function 'hy-syntax-propertize-function)

  ;; AutoHighlightSymbol needs adjustment for symbol recognition
  (setq-local ahs-include "^[0-9A-Za-z/_.,:;*+=&%|$#@!^?-~\-]+$")

  ;; Lispy comment syntax
  (setq-local comment-start ";")
  (setq-local comment-start-skip
              "\\(\\(^\\|[^\\\\\n]\\)\\(\\\\\\\\\\)*\\)\\(;+\\|#|\\) *")
  (setq-local comment-add 1)

  ;; Lispy indent with hy-specialized indentation
  (setq-local indent-tabs-mode nil)
  (setq-local indent-line-function 'hy-indent-line)
  (setq-local lisp-indent-function 'hy-indent-function))


(defun hy--mode-setup-smartparens ()
  "Setup smartparens, if active, pairs for Hy."
  (when (fboundp 'sp-local-pair)
    (sp-local-pair '(hy-mode) "`" "`" :actions nil)
    (sp-local-pair '(hy-mode) "'" "'" :actions nil)
    (sp-local-pair '(inferior-hy-mode) "`" "" :actions nil)
    (sp-local-pair '(inferior-hy-mode) "'" "" :actions nil)))

;;;; Inferior-hy-mode setup

(defun hy--inferior-setup-comint ()
  (setq-local comint-prompt-read-only t)
  (setq-local comint-use-prompt-regexp t)
  (setq-local comint-prompt-regexp hy-shell-prompt-regexp)

  (ansi-color-for-comint-mode-on)

  ;; Don't startup font lock for internal processes
  (when hy--shell-font-lock-enable
    (hy--shell-font-lock-turn-on))

  ;; Fixes issue with "=>", no side effects from this advice
  (advice-add 'comint-previous-input :before
              (lambda (&rest args) (setq-local comint-stored-incomplete-input ""))))


(defun hy--inferior-setup ()
  (setq mode-line-process '(":%s"))
  (setq-local indent-tabs-mode nil))


;;; Core

(add-to-list 'auto-mode-alist '("\\.hy\\'" . hy-mode))
(add-to-list 'interpreter-mode-alist '("hy" . hy-mode))

;;;###autoload
(define-derived-mode inferior-hy-mode comint-mode "Inferior Hy"
  "Major mode for Hy inferior process."
  (hy--inferior-setup)
  (hy--inferior-setup-comint))

;;;###autoload
(define-derived-mode hy-mode prog-mode "Hy"
  "Major mode for editing Hy files."
  (hy--mode-setup-eldoc)
  (hy--mode-setup-font-lock)
  (hy--mode-setup-internal-process)
  (hy--mode-setup-smartparens)
  (hy--mode-setup-syntax))

(set-keymap-parent hy-mode-map lisp-mode-shared-map)

(hy-define-keys
 hy-mode-map
 (kbd "C-c C-e") 'hy-shell-start-or-switch-to-shell
 (kbd "C-c C-b") 'hy-shell-eval-buffer
 (kbd "C-c C-t") 'hy-insert-pdb
 (kbd "C-c C-S-t") 'hy-insert-pdb-threaded
 (kbd "C-c C-z") 'hy-shell-start-or-switch-to-shell
 (kbd "C-c C-b") 'hy-shell-eval-buffer
 (kbd "C-c C-t") 'hy-insert-pdb
 (kbd "C-c C-S-t") 'hy-insert-pdb-threaded
 (kbd "C-c C-r") 'hy-shell-eval-region
 (kbd "C-M-x") 'hy-shell-eval-current-form
 (kbd "C-c C-e") 'hy-shell-eval-last-sexp)

(define-key inferior-hy-mode-map (kbd "C-c C-z")
  (lambda () (interactive) (other-window -1)))

(provide 'hy-mode)

;;; hy-mode.el ends here
