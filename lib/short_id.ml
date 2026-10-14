open! Core

module type S = sig
  type t [@@deriving quickcheck]

  include Identifiable.S with type t := t

  val of_string_or_error : string -> t Or_error.t
  val max_length : int

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
    end
  end
end

module Make (P : sig
    val module_name : string
    val max_length : int
    val allowed_char : char -> bool
    val sample_chars : string
  end) : S = struct
  let max_length = P.max_length

  let of_string_or_error s =
    let n = String.length s in
    let check =
      if n = 0
      then Or_error.error_s [%message "empty"]
      else if n > max_length
      then Or_error.error_s [%message "too long" (n : int) (max_length : int)]
      else (
        match String.find s ~f:(fun c -> not (P.allowed_char c)) with
        | Some c -> Or_error.error_s [%message "character not allowed" (c : char)]
        | None -> Ok ())
    in
    Or_error.tag_s check ~tag:[%message P.module_name ~id:(s : string)]
    |> Or_error.map ~f:(fun () -> s)
  ;;

  module T = struct
    type t = string [@@deriving compare, equal, hash]

    let module_name = P.module_name
    let to_string t = t
    let of_string s = Or_error.ok_exn (of_string_or_error s)
    let sexp_of_t = sexp_of_string
    let t_of_sexp sexp = of_string (string_of_sexp sexp)

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (String)
        (struct
          type t = string

          let to_binable = Fn.id
          let of_binable = of_string
        end)
  end

  include T
  include Identifiable.Make (T)

  let quickcheck_generator =
    let open Quickcheck.Generator.Let_syntax in
    let%bind len = Int.gen_incl 1 (Int.min 16 max_length) in
    String.gen_with_length len (Quickcheck.Generator.of_list (String.to_list P.sample_chars))
  ;;

  let quickcheck_observer = String.quickcheck_observer
  let quickcheck_shrinker : t Quickcheck.Shrinker.t = Quickcheck.Shrinker.empty ()

  module Stable = struct
    module V1 = T
  end
end
