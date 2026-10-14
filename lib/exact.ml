open! Core

type t = Q.t

let to_string q =
  if Q.sign q < 0
  then "-" ^ Money.Decimal_text.q_to_string (Q.neg q)
  else Money.Decimal_text.q_to_string q
;;

let of_string_or_error s =
  let negative, digits =
    match String.chop_prefix s ~prefix:"-" with
    | Some rest -> true, rest
    | None -> false, s
  in
  match Money.Decimal_text.q_of_string digits with
  | Some q -> Ok (if negative then Q.neg q else q)
  | None -> Or_error.error_s [%message "malformed exact number" s]
;;

let of_string s = Or_error.ok_exn (of_string_or_error s)

(* Eta-expanded: [let compare = Q.compare] does not match the derived signature's modes
   under OxCaml. *)
let compare a b = Q.compare a b
let equal a b = Q.equal a b
let sexp_of_t t = Sexp.Atom (to_string t)

let t_of_sexp = function
  | Sexp.Atom s as sexp ->
    (match of_string_or_error s with
     | Ok q -> q
     | Error e -> of_sexp_error (Error.to_string_hum e) sexp)
  | sexp -> of_sexp_error "Exact.t_of_sexp: expected an atom" sexp
;;

let quickcheck_generator =
  let open Quickcheck.Generator.Let_syntax in
  let%map n = Int.gen_incl (-1_000_000) 1_000_000 in
  Q.of_ints n 10_000
;;

module Stable = struct
  module V1 = struct
    type nonrec t = t

    let compare = compare
    let equal = equal
    let sexp_of_t = sexp_of_t
    let t_of_sexp = t_of_sexp

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (String)
        (struct
          type nonrec t = t

          let to_binable = to_string
          let of_binable = of_string
        end)
  end
end
