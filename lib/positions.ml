open! Core
module Time = Time_ns.Stable.Alternate_sexp.V1

module Method = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Average_cost
        | Fifo
      [@@deriving bin_io, sexp, compare, equal, enumerate]
    end
  end

  include Stable.V1
end

module Lot = struct
  module Stable = struct
    module V1 = struct
      type t =
        { size : Exact.Stable.V1.t
        ; price : Exact.Stable.V1.t
        ; opened_at : Time.t
        ; opened_by : Event_id.Stable.V1.t
        }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  type t = Stable.V1.t =
    { size : Exact.t
    ; price : Exact.t
    ; opened_at : Time_ns.Alternate_sexp.t
    ; opened_by : Event_id.t
    }
  [@@deriving sexp, compare, equal]
end

module Position = struct
  module Stable = struct
    module V1 = struct
      type t =
        { address : Address.Stable.V1.t
        ; instrument : Instrument.Stable.V1.t
        ; lots : Lot.Stable.V1.t list
        ; realised : Exact.Stable.V1.t
        }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  type t = Stable.V1.t =
    { address : Address.t
    ; instrument : Instrument.t
    ; lots : Lot.t list
    ; realised : Exact.t
    }
  [@@deriving sexp, compare, equal]

  let size t = List.fold t.lots ~init:Q.zero ~f:(fun acc (l : Lot.t) -> Q.add acc l.size)

  let cost t =
    List.fold t.lots ~init:Q.zero ~f:(fun acc (l : Lot.t) ->
      Q.add acc (Q.mul l.size l.price))
  ;;

  let average_price t =
    let size = size t in
    if Q.equal size Q.zero then None else Some (Q.div (cost t) size)
  ;;

  let unrealised t ~mark = Q.sub (Q.mul (size t) mark) (cost t)
end

module Realisation = struct
  type t =
    { event_id : Event_id.t
    ; address : Address.t
    ; instrument : Instrument.t
    ; closed : Exact.t
    ; realised : Exact.t
    ; reported : Money.Amount.t option
    }
  [@@deriving sexp, compare, equal]

  let amount t =
    Money.Amount.of_q
      ~rounding:Half_even
      (Instrument.quote_currency t.instrument)
      t.realised
  ;;

  let difference_from_reported t =
    Option.map t.reported ~f:(fun reported -> Money.Amount.sub_exn reported (amount t))
  ;;
end

module Applied = struct
  type t =
    | Applied of Realisation.t
    | Duplicate
  [@@deriving sexp, compare, equal]
end

module Key = struct
  module T = struct
    type t = Address.t * Instrument.t [@@deriving sexp, compare]
  end

  include T
  include Comparable.Make (T)
end

type t =
  { method_ : Method.t
  ; positions : Position.t Key.Map.t
  ; seen : Event_id.Set.t
  }
[@@deriving sexp_of]

let empty method_ = { method_; positions = Key.Map.empty; seen = Event_id.Set.empty }
let method_ t = t.method_
let find t ~address ~instrument = Map.find t.positions (address, instrument)

let get t ~address ~instrument =
  Option.value
    (find t ~address ~instrument)
    ~default:{ Position.address; instrument; lots = []; realised = Q.zero }
;;

let sign q = Q.sign q

(* Averages [lots] into one lot at the average price, keeping the oldest open time. *)
let average (lots : Lot.t list) =
  match lots with
  | [] | [ _ ] -> lots
  | first :: _ ->
    let size = List.fold lots ~init:Q.zero ~f:(fun acc (l : Lot.t) -> Q.add acc l.size) in
    let cost =
      List.fold lots ~init:Q.zero ~f:(fun acc (l : Lot.t) ->
        Q.add acc (Q.mul l.size l.price))
    in
    [ { first with size; price = Q.div cost size } ]
;;

(* Closes up to [remaining] (positive) from [lots], oldest first. Returns the lots left,
   the size not closed, and the profit realised. [direction] is the sign of the lots. *)
let rec close lots ~remaining ~price ~direction ~realised =
  match lots with
  | [] -> [], remaining, realised
  | _ when Q.equal remaining Q.zero -> lots, remaining, realised
  | (lot : Lot.t) :: rest ->
    let lot_size = Q.abs lot.size in
    let take = Q.min remaining lot_size in
    let gain = Q.mul (Q.mul take (Q.sub price lot.price)) (Q.of_int direction) in
    let realised = Q.add realised gain in
    let remaining = Q.sub remaining take in
    if Q.equal take lot_size
    then close rest ~remaining ~price ~direction ~realised
    else (
      let left = Q.mul (Q.sub lot_size take) (Q.of_int direction) in
      { lot with size = left } :: rest, remaining, realised)
;;

let apply t (fill : Fill.t) =
  if Set.mem t.seen fill.event_id
  then t, Applied.Duplicate
  else (
    let position = get t ~address:fill.address ~instrument:fill.instrument in
    let signed = Fill.signed_size fill in
    let current = Position.size position in
    let new_lot size : Lot.t =
      { size
      ; price = fill.price
      ; opened_at = fill.occurred_at
      ; opened_by = fill.event_id
      }
    in
    let lots, closed, realised =
      if Q.equal current Q.zero || sign current = sign signed
      then position.lots @ [ new_lot signed ], Q.zero, Q.zero
      else (
        let direction = sign current in
        let lots, remaining, realised =
          close
            position.lots
            ~remaining:fill.size
            ~price:fill.price
            ~direction
            ~realised:Q.zero
        in
        let closed = Q.sub fill.size remaining in
        if Q.equal remaining Q.zero
        then lots, closed, realised
        else [ new_lot (Q.mul remaining (Q.of_int (-direction))) ], closed, realised)
    in
    let lots =
      match t.method_ with
      | Average_cost -> average lots
      | Fifo -> lots
    in
    let position = { position with lots; realised = Q.add position.realised realised } in
    let realisation =
      { Realisation.event_id = fill.event_id
      ; address = fill.address
      ; instrument = fill.instrument
      ; closed
      ; realised
      ; reported = fill.reported_pnl
      }
    in
    ( { t with
        positions =
          Map.set t.positions ~key:(fill.address, fill.instrument) ~data:position
      ; seen = Set.add t.seen fill.event_id
      }
    , Applied.Applied realisation ))
;;

let add_lot t ~address ~instrument (lot : Lot.t) =
  let position = get t ~address ~instrument in
  let current = Position.size position in
  if Q.equal lot.size Q.zero || Q.sign lot.price <= 0
  then Or_error.error_s [%message "lot needs a non-zero size and a positive price"]
  else if (not (Q.equal current Q.zero)) && sign current <> sign lot.size
  then
    Or_error.error_s
      [%message
        "lot against the position's direction"
          ~instrument:(Instrument.to_string instrument)]
  else (
    let lots =
      match t.method_ with
      | Average_cost -> average (position.lots @ [ lot ])
      | Fifo -> position.lots @ [ lot ]
    in
    Ok
      { t with
        positions =
          Map.set t.positions ~key:(address, instrument) ~data:{ position with lots }
      })
;;

let positions t = Map.data t.positions

let open_positions t =
  List.filter (positions t) ~f:(fun p -> not (Q.equal (Position.size p) Q.zero))
;;

module Stable = struct
  module V1 = struct
    module Repr = struct
      type t =
        { method_ : Method.Stable.V1.t
        ; positions : Position.Stable.V1.t list
        ; seen : Event_id.Stable.V1.t list
        }
      [@@deriving bin_io, sexp]
    end

    type nonrec t = t

    let to_repr t =
      { Repr.method_ = t.method_
      ; positions = Map.data t.positions
      ; seen = Set.to_list t.seen
      }
    ;;

    let of_repr (r : Repr.t) =
      { method_ = r.method_
      ; positions =
          Key.Map.of_alist_exn
            (List.map r.positions ~f:(fun (p : Position.t) ->
               (p.address, p.instrument), p))
      ; seen = Event_id.Set.of_list r.seen
      }
    ;;

    let sexp_of_t t = Repr.sexp_of_t (to_repr t)
    let t_of_sexp s = of_repr (Repr.t_of_sexp s)

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (Repr)
        (struct
          type nonrec t = t

          let to_binable = to_repr
          let of_binable = of_repr
        end)
  end
end
