open! Core

module type S = sig
  val source : string

  type config
  type event
  type report

  val normalize : config -> event -> Normalized.t list Or_error.t
  val observe : config -> report -> Observed.t Or_error.t
end

let round currency q = Money.Amount.of_q ~rounding:Half_even currency q

let normalize_all
  (type c e)
  (module N : S with type config = c and type event = e)
  config
  events
  =
  List.map events ~f:(N.normalize config)
  |> Or_error.combine_errors
  |> Or_error.map ~f:List.concat
  |> Or_error.tag ~tag:N.source
;;
