(** A custody location: one venue of one on-chain account. An organisation's binding may
    include sub-accounts, so the address is part of the location. Balances at a location
    are kept per asset (a {!Money.Currency.t}). *)

open! Core

(** One venue of one address. *)
type t =
  { address : Address.t
  ; venue : Venue.t
  }
[@@deriving sexp, compare, equal, hash]

include Comparable.S with type t := t

(** [<address>:<venue>]. *)
val to_string : t -> string

(** Locations over two addresses and every venue. *)
val quickcheck_generator : t Quickcheck.Generator.t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
  end
end
