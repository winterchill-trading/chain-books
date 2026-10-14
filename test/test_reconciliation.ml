open! Core
open Chain_books
open Helpers

let show rows = List.iter rows ~f:(fun r -> print_s [%sexp (r : Reconciliation.Row.t)])

let%expect_test "matched, difference, untracked and not reported" =
  let b =
    book
      Ledger.Balances.empty
      ~at:t0
      [ activity "d1" Deposit perp (usd "100"); activity "d2" Deposit spot (hy "5") ]
  in
  show
    (Reconciliation.balances
       chart
       b
       (observed
          [ perp, usd "100"; spot, hy "4.5"; loc ~address:sub Spot, usd "7" ]));
  [%expect
    {|
    ((location ((address 0xa1) (venue Perp))) (asset USDC)
     (booked ("100.000000 USDC")) (observed ("100.000000 USDC"))
     (status Matched))
    ((location ((address 0xa1) (venue Spot))) (asset HYPE)
     (booked ("5.00000000 HYPE")) (observed ("4.50000000 HYPE"))
     (status (Difference "-0.50000000 HYPE")))
    ((location ((address 0xb2) (venue Spot))) (asset USDC) (booked ())
     (observed ("7.000000 USDC")) (status Untracked))
    |}];
  show (Reconciliation.breaks (Reconciliation.balances chart b (observed [ perp, usd "100" ])));
  [%expect
    {|
    ((location ((address 0xa1) (venue Spot))) (asset HYPE)
     (booked ("5.00000000 HYPE")) (observed ()) (status Not_reported))
    |}]
;;

let%expect_test "a tolerance absorbs rounding" =
  let b = book Ledger.Balances.empty ~at:t0 [ activity "d1" Deposit perp (usd "100") ] in
  let tolerance c = Money.Amount.of_minor_units_int c 1 in
  show (Reconciliation.balances chart ~tolerance b (observed [ perp, usd "100.000001" ]));
  [%expect
    {|
    ((location ((address 0xa1) (venue Perp))) (asset USDC)
     (booked ("100.000000 USDC")) (observed ("100.000001 USDC"))
     (status Matched))
    |}]
;;

let%expect_test "an opening balance books what the window missed, once" =
  let b = book Ledger.Balances.empty ~at:(at_min 10) [ activity "f1" Funding perp (usd "2") ] in
  let ob = { Observed.Balance.location = perp; amount = usd "50"; observed_at = at_min 20 } in
  let derived = Opening.derive chart b ob ~effective_at:t0 ~at:(at_min 20) |> Or_error.ok_exn in
  print_s [%sexp (derived : Opening.Derived.t)];
  [%expect
    {|
    ((location ((address 0xa1) (venue Perp))) (observed "50.000000 USDC")
     (booked "2.000000 USDC") (difference "48.000000 USDC")
     (entry
      (((idempotency_key chain:org1:opening:0xa1:perp:USDC)
        (kind (Transfer chain_opening)) (code Transfer_intraledger)
        (reference 0xa1:perp) (remittance_info "")
        (effective_at "2026-07-01 00:00:00Z")
        (recorded_at "2026-07-01 00:20:00Z") (business_date 2026-07-01) (sca ())
        (postings
         (((account chain:org1:custody:0xa1:perp) (side Debit)
           (amount "48.000000 USDC"))
          ((account chain:org1:cp:opening_balance) (side Credit)
           (amount "48.000000 USDC"))))))))
    |}];
  let b = open_account b (Chart.counterparty_account chart Opening_balance) in
  let b = post b (Option.value_exn derived.entry) in
  show (Reconciliation.balances chart b (Observed.merge [ observed [ perp, usd "50" ] ]));
  [%expect
    {|
    ((location ((address 0xa1) (venue Perp))) (asset USDC)
     (booked ("50.000000 USDC")) (observed ("50.000000 USDC")) (status Matched))
    |}];
  print_s
    [%sexp
      (Ledger.Balances.apply
         b
         { seq = Ledger.Balances.next_seq b; event = Posted (Option.value_exn derived.entry) }
       |> Or_error.map ~f:ignore
       : unit Or_error.t)];
  [%expect {|
    (Error
     ("idempotency key already booked"
      (idempotency_key chain:org1:opening:0xa1:perp:USDC) (booked_at 5)))
    |}]
;;

let%expect_test "positions: tracked against reported sizes" =
  let ps, _ = Positions.apply (Positions.empty Fifo) (fill "f1" Buy "2" "100") in
  let report : Observed.t =
    { balances = []
    ; positions =
        [ { address; instrument = btc_perp; size = Exact.of_string "1.5"; entry_price = None; observed_at = t0 }
        ; { address
          ; instrument = Instrument.perp ~coin:"ETH" ~settle:usdc |> Or_error.ok_exn
          ; size = Exact.of_string "-3"
          ; entry_price = None
          ; observed_at = t0
          }
        ]
    }
  in
  List.iter (Reconciliation.positions ps report) ~f:(fun r ->
    print_s [%sexp (r : Reconciliation.Position_row.t)]);
  [%expect
    {|
    ((address 0xa1) (instrument (Perp (coin BTC) (settle USDC))) (tracked 2)
     (observed 1.5) (matched false))
    ((address 0xa1) (instrument (Perp (coin ETH) (settle USDC))) (tracked 0)
     (observed -3) (matched false))
    |}]
;;

(* Random activities over a few locations; the observed balance of each location is
   computed here independently from the activity amounts. *)
let gen_activities =
  let open Quickcheck.Generator.Let_syntax in
  let locations = [ perp; spot; loc Staking; loc ~address:sub Perp ] in
  let%bind n = Int.gen_incl 1 30 in
  let%map steps =
    List.gen_with_length
      n
      (Quickcheck.Generator.tuple4
         (Quickcheck.Generator.of_list locations)
         (Quickcheck.Generator.of_list locations)
         (Int.gen_incl (-5_000) 5_000)
         (Quickcheck.Generator.of_list [ `Deposit; `Fee; `Internal; `Funding ]))
  in
  List.mapi steps ~f:(fun i (location, other, minor, kind) ->
    let amount = Money.Amount.of_minor_units_int usdc minor in
    let id = sprintf "a%d" i in
    match kind with
    | `Internal when not (Location.equal location other) ->
      activity id Internal location amount ~counter:(Location other)
    | `Internal | `Deposit -> activity id Deposit location amount
    | `Fee -> activity id Trade_fee location amount
    | `Funding -> activity id Funding location amount)
;;

let expected_balances activities =
  List.fold activities ~init:Location.Map.empty ~f:(fun acc (a : Activity.t) ->
    let add acc l x =
      Map.update acc l ~f:(fun prev ->
        Money.Amount.add_exn (Option.value prev ~default:(Money.Amount.zero usdc)) x)
    in
    let acc = add acc a.location a.amount in
    match a.counter with
    | Location other -> add acc other (Money.Amount.neg a.amount)
    | Counterparty _ -> acc)
;;

let%test_unit "booked balances equal the activity sums and the ledger stays balanced" =
  Quickcheck.test gen_activities ~trials:300 ~f:(fun activities ->
    let b = book Ledger.Balances.empty ~at:t0 activities in
    Ledger.Trial_balance.check (Ledger.Trial_balance.of_balances b) |> Or_error.ok_exn;
    let report =
      observed (Map.to_alist (expected_balances activities))
    in
    [%test_result: Reconciliation.Row.t list]
      (Reconciliation.breaks (Reconciliation.balances chart b report))
      ~expect:[];
    (* Booking the same history again changes no balance. *)
    let again =
      List.fold activities ~init:b ~f:(fun b a ->
        match Booking.entry chart ~at:t0 a |> Or_error.ok_exn with
        | Skipped _ -> b
        | Entry e ->
          (match Ledger.Balances.find_entry b e.idempotency_key with
           | Some _ -> b
           | None -> post b e))
    in
    [%test_result: Reconciliation.Row.t list]
      (Reconciliation.balances chart again report)
      ~expect:(Reconciliation.balances chart b report))
;;
