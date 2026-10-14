open! Core

module Mark = struct
  type t =
    { price : Exact.t
    ; at : Time_ns.Alternate_sexp.t
    }
  [@@deriving sexp, compare, equal]
end

type t =
  { rate : base:Money.Currency.t -> quote:Money.Currency.t -> Money.Rate.t option
  ; mark : Instrument.t -> Mark.t option
  }

let create ~rate ~mark = { rate; mark }

let latest_by ~at items =
  List.max_elt items ~compare:(fun a b -> Time_ns.compare (at a) (at b))
;;

let of_table ?(rates = []) ?(marks = []) () =
  let rate ~base ~quote =
    List.filter_map rates ~f:(fun r ->
      let b = Money.Rate.base r
      and q = Money.Rate.quote r in
      if Money.Currency.equal b base && Money.Currency.equal q quote
      then Some r
      else if Money.Currency.equal b quote && Money.Currency.equal q base
      then Some (Money.Rate.inverse r)
      else None)
    |> latest_by ~at:Money.Rate.at
  in
  let mark instrument =
    List.filter_map marks ~f:(fun (i, m) ->
      if Instrument.equal i instrument then Some m else None)
    |> latest_by ~at:(fun (m : Mark.t) -> m.at)
  in
  { rate; mark }
;;

let rate t ~base ~quote =
  if Money.Currency.equal base quote then None else t.rate ~base ~quote
;;

let mark t instrument = t.mark instrument
