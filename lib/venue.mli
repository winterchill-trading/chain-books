(** Where inside an account an asset sits: a perpetuals margin account (the default one,
    or one per perpetuals exchange deployed on the same chain), the spot account, accrued
    but unclaimed rewards, vault equity or staked tokens. A venue is part of a
    {!Location}; each one is booked to its own ledger account. *)

open! Core

type t =
  | Perp
  | Perp_dex of string
  (** a separately margined perpetuals exchange, by name (1 to 16 letters and digits) *)
  | Spot
  | Rewards
  | Vault
  | Staking
[@@deriving sexp, compare, equal, hash]

include Comparable.S with type t := t

(** [perp], [perp:<dex>], [spot], [rewards], [vault], [staking]. *)
val to_string : t -> string

(** Parses {!to_string}; fails on anything else, including a malformed dex name. *)
val of_string_or_error : string -> t Or_error.t

(** [Perp_dex dex] with the name checked. *)
val perp_dex : string -> t Or_error.t

(** [Perp] or a [Perp_dex]. *)
val is_perp : t -> bool

val quickcheck_generator : t Quickcheck.Generator.t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
  end
end
