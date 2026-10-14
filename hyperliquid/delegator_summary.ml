open! Core

type t =
  { delegated : Chain_books.Exact.t
  ; undelegated : Chain_books.Exact.t
  ; total_pending_withdrawal : Chain_books.Exact.t
  }
[@@deriving sexp_of]

let staking_balance t =
  Q.add t.delegated (Q.add t.undelegated t.total_pending_withdrawal)
;;

let of_json json =
  { delegated = Wire.decimal json "delegated"
  ; undelegated = Wire.decimal json "undelegated"
  ; total_pending_withdrawal = Wire.decimal_or_zero json "totalPendingWithdrawal"
  }
;;

let of_yojson = Wire.decode ~what:"delegator summary" of_json
