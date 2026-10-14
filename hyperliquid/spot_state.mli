(** The [spotClearinghouseState] info answer: spot balances per token.

    {v
    {"balances": [{"coin": "USDC", "token": 0, "total": "0.00524174", "hold": "0.0", "entryNtl": "0.0"}]}
    v}

    [total] includes [hold] (funds reserved by open orders). Spot USDC is reported with 8
    decimals while the books keep USDC at 6, so an observed spot balance is rounded and
    reconciliation needs a tolerance of one minor unit. *)

open! Core

module Balance : sig
  type t =
    { coin : string
    ; total : Q.t
    }
  [@@deriving sexp_of]
end

type t = { balances : Balance.t list } [@@deriving sexp_of]

val of_yojson : Yojson.Safe.t -> t Or_error.t
