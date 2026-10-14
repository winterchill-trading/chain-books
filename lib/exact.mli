(** Exact rational quantities and prices ([Q.t]) for sizes and prices that are not
    amounts of a currency: perpetual contract sizes, prices quoted per unit. Written as a
    signed decimal (["-1.25"]) when the decimal terminates and as a fraction (["1/3"])
    otherwise, in sexps and in bin_prot. *)

open! Core

type t = Q.t [@@deriving sexp, compare, equal]

(** Parses an optional ['-'] followed by digits, a decimal or a fraction. *)
val of_string_or_error : string -> t Or_error.t

(** Raises on malformed input. *)
val of_string : string -> t

val to_string : t -> string

(** Small decimals with up to four fractional digits, both signs. *)
val quickcheck_generator : t Quickcheck.Generator.t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
