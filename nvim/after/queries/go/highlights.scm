;; extends

; upstream captures "chan"/"map" as @type.builtin alongside builtin type
; names, so `chan string` renders as a single colour. re-capture them as
; keywords so the keyword and its element type read distinctly
[
  "chan"
  "map"
] @keyword

; gopls tokenises an import path as a namespace, which nvim links to @module,
; but the token covers the path text and not the quotes around it, so the
; literal renders in two colours. capture the whole thing to match, which also
; lines the import block up with the package qualifier at the use site
(import_spec
  path: [
    (interpreted_string_literal)
    (raw_string_literal)
  ] @module)
