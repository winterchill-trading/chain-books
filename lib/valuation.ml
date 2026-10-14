open! Core

module Missing = struct
  type what =
    | Rate of Money.Currency.t
    | Mark of Instrument.t
  [@@deriving sexp, compare, equal]

  type t =
    { what : what
    ; stale_since : Time_ns.Alternate_sexp.t option
    }
  [@@deriving sexp, compare, equal]
end

module Line = struct
  type t =
    { location : Location.t
    ; balance : Money.Amount.t
    ; value : Money.Amount.t option
    }
  [@@deriving sexp, compare, equal]
end

module Position_line = struct
  type t =
    { address : Address.t
    ; instrument : Instrument.t
    ; size : Exact.t
    ; average_price : Exact.t option
    ; mark : Exact.t option
    ; unrealised : Money.Amount.t option
    }
  [@@deriving sexp, compare, equal]
end

type t =
  { currency : Money.Currency.t
  ; at : Time_ns.Alternate_sexp.t
  ; lines : Line.t list
  ; positions : Position_line.t list
  ; total : Money.Amount.t
  ; missing : Missing.t list
  }
[@@deriving sexp, compare, equal]

let fresh ~max_age ~now at =
  match max_age with
  | None -> true
  | Some max_age -> Time_ns.Span.( <= ) (Time_ns.diff now at) max_age
;;

(* The price of one unit of [asset] in [currency], exact, or why there is none. *)
let conversion prices ~max_age ~now ~currency asset : (Q.t, Missing.t) Result.t =
  if Money.Currency.equal asset currency
  then Ok Q.one
  else (
    match Price_source.rate prices ~base:asset ~quote:currency with
    | None -> Error { what = Rate asset; stale_since = None }
    | Some rate when fresh ~max_age ~now (Money.Rate.at rate) ->
      Ok (Money.Rate.price rate)
    | Some rate -> Error { what = Rate asset; stale_since = Some (Money.Rate.at rate) })
;;

let value chart ?max_age balances positions prices ~currency ~now =
  let missing = ref [] in
  let note m = missing := m :: !missing in
  let total = ref Q.zero in
  let round q = Money.Amount.of_q ~rounding:Half_even currency q in
  let lines =
    List.concat_map
      (Ledger.Balances.accounts balances)
      ~f:(fun (account : Ledger.Account.t) ->
        match Chart.location_of_account chart account.id with
        | None -> []
        | Some location ->
          List.filter_map
            (Ledger.Balances.currencies balances account.id)
            ~f:(fun asset ->
              let balance = Ledger.Balances.posted balances account.id asset in
              if Money.Amount.is_zero balance
              then None
              else (
                let value =
                  match conversion prices ~max_age ~now ~currency asset with
                  | Error m ->
                    note m;
                    None
                  | Ok price ->
                    let v = Q.mul (Money.Amount.to_q balance) price in
                    total := Q.add !total v;
                    Some (round v)
                in
                Some { Line.location; balance; value })))
  in
  let positions =
    List.map (Positions.open_positions positions) ~f:(fun (p : Positions.Position.t) ->
      let quote = Instrument.quote_currency p.instrument in
      let mark =
        match Price_source.mark prices p.instrument with
        | None ->
          note { what = Mark p.instrument; stale_since = None };
          None
        | Some m when fresh ~max_age ~now m.at -> Some m.price
        | Some m ->
          note { what = Mark p.instrument; stale_since = Some m.at };
          None
      in
      let unrealised =
        let%bind.Option mark in
        match conversion prices ~max_age ~now ~currency quote with
        | Error m ->
          note m;
          None
        | Ok price ->
          let v = Q.mul (Positions.Position.unrealised p ~mark) price in
          total := Q.add !total v;
          Some (round v)
      in
      { Position_line.address = p.address
      ; instrument = p.instrument
      ; size = Positions.Position.size p
      ; average_price = Positions.Position.average_price p
      ; mark
      ; unrealised
      })
  in
  { currency
  ; at = now
  ; lines
  ; positions
  ; total = round !total
  ; missing = List.dedup_and_sort !missing ~compare:Missing.compare
  }
;;
