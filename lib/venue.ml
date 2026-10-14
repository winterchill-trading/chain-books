open! Core

module Stable = struct
  module V1 = struct
    type t =
      | Perp
      | Perp_dex of string
      | Spot
      | Rewards
      | Vault
      | Staking
    [@@deriving bin_io, sexp, compare, equal, hash]
  end
end

module T = struct
  include Stable.V1

  let check_dex dex =
    if String.length dex >= 1
       && String.length dex <= 16
       && String.for_all dex ~f:Char.is_alphanum
    then Ok ()
    else Or_error.error_s [%message "invalid perp dex name" (dex : string)]
  ;;

  (* Reading a sexp validates the dex name like [perp_dex] does. *)
  let t_of_sexp sexp =
    let t = t_of_sexp sexp in
    match t with
    | Perp_dex dex ->
      Or_error.ok_exn (check_dex dex);
      t
    | Perp | Spot | Rewards | Vault | Staking -> t
  ;;
end

include T

let perp_dex dex = Or_error.map (check_dex dex) ~f:(fun () -> Perp_dex dex)

let to_string = function
  | Perp -> "perp"
  | Perp_dex dex -> "perp:" ^ dex
  | Spot -> "spot"
  | Rewards -> "rewards"
  | Vault -> "vault"
  | Staking -> "staking"
;;

let of_string_or_error s =
  match s with
  | "perp" -> Ok Perp
  | "spot" -> Ok Spot
  | "rewards" -> Ok Rewards
  | "vault" -> Ok Vault
  | "staking" -> Ok Staking
  | _ ->
    (match String.chop_prefix s ~prefix:"perp:" with
     | Some dex -> perp_dex dex
     | None -> Or_error.error_s [%message "unknown venue" s])
;;

let is_perp = function
  | Perp | Perp_dex _ -> true
  | Spot | Rewards | Vault | Staking -> false
;;

let quickcheck_generator =
  Quickcheck.Generator.of_list
    [ Perp; Perp_dex "xyz"; Perp_dex "flx"; Spot; Rewards; Vault; Staking ]
;;

include Comparable.Make (T)
