(** One staking reward: an item of the [delegatorRewards] info request.

    {v
    {"time": 1791936000012, "source": "delegation", "totalAmount": "6.05586226"}
    v}

    Rewards are in HYPE and are added to the staking balance. [source] is [delegation]
    or [commission] (for a validator). *)

open! Core

type t =
  { time : int
  ; source : string
  ; total_amount : Q.t
  }
[@@deriving sexp_of]

val of_yojson : Yojson.Safe.t -> t Or_error.t
val list_of_yojson : Yojson.Safe.t -> t list Or_error.t
