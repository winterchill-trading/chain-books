open! Core

module Stable = struct
  module V1 = struct
    type t =
      { address : Address.Stable.V1.t
      ; venue : Venue.Stable.V1.t
      }
    [@@deriving bin_io, sexp, compare, equal, hash]
  end
end

module T = struct
  type t = Stable.V1.t =
    { address : Address.t
    ; venue : Venue.t
    }
  [@@deriving sexp, compare, equal, hash]
end

include T

let to_string { address; venue } =
  Address.to_string address ^ ":" ^ Venue.to_string venue
;;

let quickcheck_generator =
  let open Quickcheck.Generator.Let_syntax in
  let%map address = Quickcheck.Generator.of_list [ "0xa1"; "0xb2" ]
  and venue = Venue.quickcheck_generator in
  { address = Address.of_string address; venue }
;;

include Comparable.Make (T)
