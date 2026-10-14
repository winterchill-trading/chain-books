(** What a {!Normalizer} produces from one venue record: cash movements to book and fills
    to track. *)

open! Core

type t =
  | Activity of Activity.t
  | Fill of Fill.t
[@@deriving sexp, compare, equal]

(** The activities, in order. *)
val activities : t list -> Activity.t list

(** The fills, in order. *)
val fills : t list -> Fill.t list

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
