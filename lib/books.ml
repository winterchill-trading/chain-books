open! Core

module Opened = struct
  module T = struct
    type t = Location.t * Money.Currency.t [@@deriving sexp, compare]
  end

  include T
  include Comparable.Make (T)
end

type t =
  { chart : Chart.t
  ; follow : Money.Currency.Set.t option
  ; classify : Activity.t -> Category.t option
  ; balances : Ledger.Balances.t
  ; positions : Positions.t
  ; opened : Opened.Set.t
  ; records_rev : Ledger.Record.t list
  }

let create ?(method_ = Positions.Method.Fifo) ?follow ?(classify = fun _ -> None) chart =
  { chart
  ; follow = Option.map follow ~f:Money.Currency.Set.of_list
  ; classify
  ; balances = Ledger.Balances.empty
  ; positions = Positions.empty method_
  ; opened = Opened.Set.empty
  ; records_rev = []
  }
;;

let chart t = t.chart
let balances t = t.balances
let positions t = t.positions
let records t = List.rev t.records_rev

let balance t location asset =
  Ledger.Balances.posted t.balances (Chart.custody t.chart location) asset
;;

module Report = struct
  type t =
    { booked : Event_id.t list
    ; duplicates : Event_id.t list
    ; skipped : (Event_id.t * Booking.Skip_reason.t) list
    ; realised : Positions.Realisation.t list
    ; repeated_fills : Event_id.t list
    }
  [@@deriving sexp_of]
end

let append t event =
  let record = { Ledger.Record.seq = Ledger.Balances.next_seq t.balances; event } in
  let%map.Or_error balances = Ledger.Balances.apply t.balances record in
  { t with balances; records_rev = record :: t.records_rev }
;;

let open_accounts t accounts =
  List.fold_result accounts ~init:t ~f:(fun t (account : Ledger.Account.t) ->
    match Ledger.Balances.find_account t.balances account.id with
    | Some _ -> Ok t
    | None -> append t (Account_opened account))
;;

(* The ledger refuses a [recorded_at] before the last record's. *)
let ledger_time t at =
  match Ledger.Balances.last_recorded_at t.balances with
  | Some last when Time_ns.( < ) at last -> last
  | Some _ | None -> at
;;

(* [`Booked], or [`Duplicate] when the same entry is already booked under its key. *)
let post t (entry : Ledger.Entry.t) =
  match Ledger.Balances.find_entry t.balances entry.idempotency_key with
  | Some (_, booked) when Ledger.Entry.same_request booked entry -> Ok (t, `Duplicate)
  | Some (_, _) ->
    Or_error.error_s
      [%message
        "event id already booked for a different movement"
          ~idempotency_key:(entry.idempotency_key : Ledger.Idempotency_key.t)]
  | None ->
    let%map.Or_error t = append t (Posted entry) in
    t, `Booked
;;

let ingest t items ~at =
  let at = ledger_time t at in
  let activities = Normalized.activities items in
  let%bind.Or_error t =
    open_accounts t (Chart.missing_accounts t.chart ~classify:t.classify t.balances activities)
  in
  let empty =
    { Report.booked = []; duplicates = []; skipped = []; realised = []; repeated_fills = [] }
  in
  let%map.Or_error t, report =
    List.fold_result items ~init:(t, empty) ~f:(fun (t, report) item ->
      match item with
      | Normalized.Fill fill ->
        let positions, applied = Positions.apply t.positions fill in
        let report =
          match applied with
          | Applied r -> { report with realised = r :: report.realised }
          | Duplicate -> { report with repeated_fills = fill.event_id :: report.repeated_fills }
        in
        Ok ({ t with positions }, report)
      | Activity activity ->
        (match%bind.Or_error
           Booking.entry t.chart ~classify:t.classify ?follow:t.follow ~at activity
         with
         | Skipped { event_id; reason } ->
           Ok (t, { report with skipped = (event_id, reason) :: report.skipped })
         | Entry entry ->
           let%map.Or_error t, outcome = post t entry in
           (match outcome with
            | `Booked -> t, { report with booked = activity.event_id :: report.booked }
            | `Duplicate ->
              t, { report with duplicates = activity.event_id :: report.duplicates })))
  in
  ( t
  , { Report.booked = List.rev report.booked
    ; duplicates = List.rev report.duplicates
    ; skipped = List.rev report.skipped
    ; realised = List.rev report.realised
    ; repeated_fills = List.rev report.repeated_fills
    } )
;;

let is_opened t location asset = Set.mem t.opened (location, asset)

let followed t asset =
  match t.follow with
  | None -> true
  | Some follow -> Set.mem follow asset
;;

let open_balances t (observed : Observed.t) ~history_start ~at =
  let at = ledger_time t at in
  let%bind.Or_error t =
    open_accounts t [ Chart.counterparty_account t.chart Opening_balance ]
  in
  let%map.Or_error t, derived =
    List.fold_result observed.balances ~init:(t, []) ~f:(fun (t, derived) balance ->
      let asset = Money.Amount.currency balance.amount in
      if is_opened t balance.location asset || not (followed t asset)
      then Ok (t, derived)
      else (
        let%bind.Or_error t =
          open_accounts t [ Chart.custody_account t.chart balance.location ]
        in
        let%bind.Or_error d =
          Opening.derive t.chart t.balances balance ~effective_at:history_start ~at
        in
        let%map.Or_error t =
          match d.entry with
          | None -> Ok t
          | Some entry -> post t entry |> Or_error.map ~f:fst
        in
        { t with opened = Set.add t.opened (balance.location, asset) }, d :: derived))
  in
  t, List.rev derived
;;

let reconcile ?tolerance t observed =
  Reconciliation.balances t.chart ?tolerance t.balances observed
;;

let reconcile_positions t observed = Reconciliation.positions t.positions observed

let value ?max_age t prices ~currency ~now =
  Valuation.value t.chart ?max_age t.balances t.positions prices ~currency ~now
;;
