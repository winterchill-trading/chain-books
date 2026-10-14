(** Builder-fee income from one fill routed through the account's builder code: a row of
    the daily builder fills file the venue publishes for a builder. The caller reads the
    file; this is the row the adapter books. *)

open! Core

type t =
  { tid : int (** the trade id, unique per fill *)
  ; time : int
  ; coin : string
  ; fee : Q.t (** the builder's share, in USDC *)
  }
[@@deriving sexp_of]
