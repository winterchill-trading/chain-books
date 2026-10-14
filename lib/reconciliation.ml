open! Core

module Status = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Matched
        | Difference of Money.Amount.Stable.V1.t
        | Untracked
        | Not_reported
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  type t = Stable.V1.t =
    | Matched
    | Difference of Money.Amount.t
    | Untracked
    | Not_reported
  [@@deriving sexp, compare, equal]
end

module Row = struct
  module Stable = struct
    module V1 = struct
      type t =
        { location : Location.Stable.V1.t
        ; asset : Money.Currency.Stable.V1.t
        ; booked : Money.Amount.Stable.V1.t option
        ; observed : Money.Amount.Stable.V1.t option
        ; status : Status.Stable.V1.t
        }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  type t = Stable.V1.t =
    { location : Location.t
    ; asset : Money.Currency.t
    ; booked : Money.Amount.t option
    ; observed : Money.Amount.t option
    ; status : Status.t
    }
  [@@deriving sexp, compare, equal]
end

module Position_row = struct
  type t =
    { address : Address.t
    ; instrument : Instrument.t
    ; tracked : Exact.t
    ; observed : Exact.t
    ; matched : bool
    }
  [@@deriving sexp, compare, equal]
end

module Key = struct
  module T = struct
    type t = Location.t * Money.Currency.t [@@deriving sexp, compare]
  end

  include T
  include Comparable.Make (T)
end

let booked_balances chart balances =
  List.concat_map (Ledger.Balances.accounts balances) ~f:(fun (account : Ledger.Account.t) ->
    match Chart.location_of_account chart account.id with
    | None -> []
    | Some location ->
      List.map (Ledger.Balances.currencies balances account.id) ~f:(fun asset ->
        (location, asset), Ledger.Balances.posted balances account.id asset))
  |> Key.Map.of_alist_exn
;;

let observed_balances (observed : Observed.t) =
  (* A report listing the same location and asset twice (two reads merged) keeps the
     latest observation. *)
  List.sort observed.balances ~compare:(fun (a : Observed.Balance.t) b ->
    Time_ns.compare a.observed_at b.observed_at)
  |> List.fold ~init:Key.Map.empty ~f:(fun acc (b : Observed.Balance.t) ->
    Map.set acc ~key:(b.location, Money.Amount.currency b.amount) ~data:b.amount)
;;

let balances chart ?tolerance ledger observed =
  let booked = booked_balances chart ledger in
  let reported = observed_balances observed in
  Map.merge booked reported ~f:(fun ~key:(location, asset) data ->
    let booked, observed =
      match data with
      | `Left b -> Some b, None
      | `Right o -> None, Some o
      | `Both (b, o) -> Some b, Some o
    in
    let zero_or_none = Option.for_all ~f:Money.Amount.is_zero in
    if zero_or_none booked && zero_or_none observed
    then None
    else (
      let status : Status.t =
        match booked, observed with
        | None, _ -> Untracked
        | Some _, None -> Not_reported
        | Some b, Some o ->
          let difference = Money.Amount.sub_exn o b in
          let tolerance =
            match tolerance with
            | None -> Money.Amount.zero asset
            | Some f -> Money.Amount.abs (f asset)
          in
          if Money.Amount.compare_value (Money.Amount.abs difference) tolerance
             |> Or_error.ok_exn
             <= 0
          then Matched
          else Difference difference
      in
      Some { Row.location; asset; booked; observed; status }))
  |> Map.data
;;

module Position_key = struct
  module T = struct
    type t = Address.t * Instrument.t [@@deriving sexp, compare]
  end

  include T
  include Comparable.Make (T)
end

let positions tracked (observed : Observed.t) =
  let tracked =
    List.filter_map (Positions.open_positions tracked) ~f:(fun p ->
      match p.instrument with
      | Perp _ -> Some ((p.address, p.instrument), Positions.Position.size p)
      | Spot _ -> None)
    |> Position_key.Map.of_alist_exn
  in
  let reported =
    List.fold observed.positions ~init:Position_key.Map.empty ~f:(fun acc p ->
      Map.set acc ~key:(p.address, p.instrument) ~data:p.size)
  in
  Map.merge tracked reported ~f:(fun ~key:(address, instrument) data ->
    let tracked, observed =
      match data with
      | `Left t -> t, Q.zero
      | `Right o -> Q.zero, o
      | `Both (t, o) -> t, o
    in
    if Q.equal tracked Q.zero && Q.equal observed Q.zero
    then None
    else
      Some
        { Position_row.address
        ; instrument
        ; tracked
        ; observed
        ; matched = Q.equal tracked observed
        })
  |> Map.data
;;

let breaks rows =
  List.filter rows ~f:(fun (r : Row.t) ->
    match r.status with
    | Matched -> false
    | Difference _ | Untracked | Not_reported -> true)
;;
