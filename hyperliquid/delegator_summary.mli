(** The [delegatorSummary] info answer: HYPE in the staking account.

    {v
    {"delegated": "0.0", "undelegated": "41.59358414", "totalPendingWithdrawal": "0.0", "nPendingWithdrawals": 0}
    v} *)

open! Core

(** The amounts, exact. *)
type t =
  { delegated : Q.t
  ; undelegated : Q.t
  ; total_pending_withdrawal : Q.t
  }
[@@deriving sexp_of]

(** Everything still in the staking account: delegated, undelegated and pending withdrawal
    to spot. *)
val staking_balance : t -> Q.t

(** Decodes the answer. *)
val of_yojson : Yojson.Safe.t -> t Or_error.t
