open! Core

module Stable = struct
  module V1 = struct
    type t =
      | Activity of Activity.Stable.V1.t
      | Fill of Fill.Stable.V1.t
    [@@deriving bin_io, sexp, compare, equal]
  end
end

type t = Stable.V1.t =
  | Activity of Activity.t
  | Fill of Fill.t
[@@deriving sexp, compare, equal]

let activities ts =
  List.filter_map ts ~f:(function
    | Activity a -> Some a
    | Fill _ -> None)
;;

let fills ts =
  List.filter_map ts ~f:(function
    | Fill f -> Some f
    | Activity _ -> None)
;;
