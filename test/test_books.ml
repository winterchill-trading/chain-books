open! Core
open Chain_books
open Helpers

let history =
  [ Normalized.Activity (activity "d1" Deposit perp (usd "500") ~at:(at_min 1))
  ; Fill (fill "t1" Buy "0.01" "60000" ~at:(at_min 2))
  ; Activity (activity "t1:fee" Trade_fee perp (usd "-0.27") ~market:"BTC" ~at:(at_min 2))
  ; Fill (fill "t2" Sell "0.01" "61000" ~reported_pnl:(usd "10") ~at:(at_min 3))
  ; Activity (activity "t2:pnl" Trade perp (usd "10") ~market:"BTC" ~at:(at_min 3))
  ; Activity (activity "t2:fee" Trade_fee perp (usd "-0.27") ~market:"BTC" ~at:(at_min 3))
  ; Activity (activity "x1" Internal perp (usd "-100") ~counter:(Location spot) ~at:(at_min 4))
  ; Activity (activity "h1" Deposit spot (hy "0") ~at:(at_min 5))
  ]
;;

let%expect_test "ingest books, tracks and reports; a second ingest only finds duplicates" =
  let books = Books.create chart in
  let books, report = Books.ingest books history ~at:(at_min 10) |> Or_error.ok_exn in
  print_s [%sexp (report : Books.Report.t)];
  [%expect
    {|
    ((booked (d1 t1:fee t2:pnl t2:fee x1)) (duplicates ())
     (skipped ((h1 Zero_amount)))
     (realised
      (((event_id t1) (address 0xa1) (instrument (Perp (coin BTC) (settle USDC)))
        (closed 0) (realised 0) (reported ()))
       ((event_id t2) (address 0xa1) (instrument (Perp (coin BTC) (settle USDC)))
        (closed 0.01) (realised 10) (reported ("10.000000 USDC")))))
     (repeated_fills ()))
    |}];
  print_amount (Books.balance books perp usdc);
  print_amount (Books.balance books spot usdc);
  [%expect
    {|
    409.460000 USDC
    100.000000 USDC
    |}];
  let again, report = Books.ingest books history ~at:(at_min 20) |> Or_error.ok_exn in
  print_s [%sexp (report : Books.Report.t)];
  [%expect
    {|
    ((booked ()) (duplicates (d1 t1:fee t2:pnl t2:fee x1))
     (skipped ((h1 Zero_amount))) (realised ()) (repeated_fills (t1 t2)))
    |}];
  print_s [%sexp (List.length (Books.records again) = List.length (Books.records books) : bool)];
  [%expect {| true |}]
;;

let%expect_test "an event id reused for another movement is refused, keeping nothing" =
  let books, _ = Books.ingest (Books.create chart) (List.take history 1) ~at:t0 |> Or_error.ok_exn in
  let clash =
    [ Normalized.Activity (activity "d2" Deposit perp (usd "1"))
    ; Activity (activity "d1" Deposit perp (usd "999"))
    ]
  in
  print_s
    [%sexp (Books.ingest books clash ~at:t0 |> Or_error.map ~f:ignore : unit Or_error.t)];
  [%expect
    {|
    (Error
     ("event id already booked for a different movement"
      (idempotency_key chain:org1:d1)))
    |}];
  print_amount (Books.balance books perp usdc);
  [%expect {| 500.000000 USDC |}]
;;

let%expect_test "openings close the gap to the first report, once" =
  let books, _ = Books.ingest (Books.create chart) history ~at:(at_min 10) |> Or_error.ok_exn in
  let report = observed ~at:(at_min 30) [ perp, usd "1409.46"; spot, usd "100"; spot, hy "12" ] in
  let books, derived =
    Books.open_balances books report ~history_start:t0 ~at:(at_min 30) |> Or_error.ok_exn
  in
  List.iter derived ~f:(fun d ->
    print_s
      [%message
        (Location.to_string d.location) ~difference:(Money.Amount.to_string d.difference)]);
  [%expect
    {|
    (0xa1:perp (difference "1000.000000 USDC"))
    (0xa1:spot (difference "0.000000 USDC"))
    (0xa1:spot (difference "12.00000000 HYPE"))
    |}];
  print_s [%sexp (Reconciliation.breaks (Books.reconcile books report) : Reconciliation.Row.t list)];
  [%expect {| () |}];
  let later = observed ~at:(at_min 40) [ perp, usd "1400"; spot, usd "100"; spot, hy "12" ] in
  let books, derived =
    Books.open_balances books later ~history_start:t0 ~at:(at_min 40) |> Or_error.ok_exn
  in
  print_s [%sexp (List.length derived : int)];
  [%expect {| 0 |}];
  List.iter (Reconciliation.breaks (Books.reconcile books later)) ~f:(fun r ->
    print_s [%sexp (r.status : Reconciliation.Status.t)]);
  [%expect {| (Difference "-9.460000 USDC") |}]
;;

let gen_history =
  let open Quickcheck.Generator.Let_syntax in
  let%bind n = Int.gen_incl 0 25 in
  let%map steps =
    List.gen_with_length
      n
      (Quickcheck.Generator.tuple3
         (Int.gen_incl 0 7)
         (Int.gen_incl (-2_000) 2_000)
         Bool.quickcheck_generator)
  in
  List.mapi steps ~f:(fun i (k, minor, buy) ->
    let id = sprintf "e%d" i in
    let amount = Money.Amount.of_minor_units_int usdc minor in
    match k with
    | 0 -> Normalized.Fill (fill id (if buy then Buy else Sell) "0.5" (Int.to_string (abs minor + 1)))
    | 1 -> Activity (activity id Internal perp amount ~counter:(Location spot))
    | 2 -> Activity (activity id Funding perp amount)
    | 3 -> Activity (activity id Trade_fee perp amount)
    | 4 -> Activity (activity id Deposit spot amount)
    | 5 -> Activity (activity id Staking spot (Money.Amount.of_minor_units_int hype minor) ~counter:(Location (loc Staking)))
    | 6 -> Activity (activity id Builder_fee (loc Rewards) amount)
    | _ -> Activity (activity id Withdrawal perp amount))
;;

let%test_unit "ingesting a history twice equals ingesting it once; the ledger balances" =
  Quickcheck.test gen_history ~trials:300 ~f:(fun history ->
    let once, _ = Books.ingest (Books.create chart) history ~at:t0 |> Or_error.ok_exn in
    let twice, report = Books.ingest once history ~at:t0 |> Or_error.ok_exn in
    [%test_result: int] (List.length report.booked) ~expect:0;
    [%test_result: int] (List.length (Books.records twice)) ~expect:(List.length (Books.records once));
    [%test_result: Positions.Position.t list]
      (Positions.positions (Books.positions twice))
      ~expect:(Positions.positions (Books.positions once));
    Ledger.Trial_balance.check (Ledger.Trial_balance.of_balances (Books.balances once))
    |> Or_error.ok_exn;
    (* Replaying the records from scratch rebuilds the same balances. *)
    let replayed = Ledger.Balances.of_records (Books.records once) |> Or_error.ok_exn in
    assert (Ledger.Balances.equal replayed (Books.balances once)))
;;
