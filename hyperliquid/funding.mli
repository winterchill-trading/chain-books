(** One funding payment of one perpetual position: an item of the [userFunding] info
    request, or a [funding] message of the [userEvents] websocket subscription.

    {v
    {"time": 1791072000000, "hash": "0x0000...", "delta": {"type": "funding", "coin": "ARB", "usdc": "0.026784", "szi": "-445.4041666667", "fundingRate": "0.000012358", "nSamples": 24}}
    v}

    [usdc] is signed from the account's side: positive when funding was received. The hash
    is all zeros on mainnet, so payments are identified by time and coin. [szi] can carry
    more digits than [Hl_protocol.Size] holds (an average over the hour), which is why
    this module decodes the history itself. *)

open! Core

type t =
  { time : int
  ; coin : string (** [ARB], or [xyz:GOLD] on another perpetuals dex *)
  ; usdc : Q.t
  }
[@@deriving sexp_of]

(** An item of the [userFunding] answer. *)
val of_yojson : Yojson.Safe.t -> t Or_error.t

(** The whole [userFunding] answer. *)
val list_of_yojson : Yojson.Safe.t -> t list Or_error.t

(** A websocket funding message. *)
val of_user_event : Hl_protocol.User_event.Funding.t -> t
