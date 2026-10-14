open! Core

type t =
  { tid : int
  ; time : int
  ; coin : string
  ; fee : Chain_books.Exact.t
  }
[@@deriving sexp_of]
