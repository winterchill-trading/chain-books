open! Core
open Chain_books
module Hl = Chain_books_hyperliquid

let read name = Yojson.Safe.from_file ("fixtures/" ^ name)
let a1 = Hl_protocol.Address.of_string "0x00000000000000000000000000000000000000a1"
let b2 = Hl_protocol.Address.of_string "0x00000000000000000000000000000000000000b2"
let config = Hl.Config.create a1 ~binding:[ b2 ] ~spot_pairs:[ "@107", ("HYPE", "USDC") ]

let short_location (l : Location.t) =
  let a = Address.to_string l.address in
  String.suffix a 2 ^ ":" ^ Venue.to_string l.venue
;;

let show items =
  List.iter items ~f:(function
    | Normalized.Fill f ->
      printf
        "fill %s %s %s %s @ %s\n"
        (Event_id.to_string f.event_id)
        (Instrument.to_string f.instrument)
        (Sexp.to_string [%sexp (f.side : Fill.Side.t)])
        (Exact.to_string f.size)
        (Exact.to_string f.price)
    | Activity a ->
      let counter =
        match a.counter with
        | Location l -> short_location l
        | Counterparty c -> Category.to_string c
      in
      printf
        "%-44s %-16s %-10s %18s  <-> %s\n"
        (Event_id.to_string a.event_id)
        (Activity.Kind.to_string a.kind)
        (short_location a.location)
        (Money.Amount.to_string a.amount)
        counter)
;;

let ledger_updates () =
  Hl.Ledger_update.list_of_yojson (read "ledger_updates.json") |> ok_exn
;;

let%expect_test "ledger updates" =
  let events = List.map (ledger_updates ()) ~f:(fun u -> Hl.Adapter.Ledger_update u) in
  show (Normalizer.normalize_all (module Hl.Adapter) config events |> ok_exn);
  [%expect
    {|
    lu:1782864060000:01010101010101010101010101010101:deposit deposit          a1:perp      1000.000000 USDC  <-> bridge
    lu:1782864120000:02020202020202020202020202020202:accountClassTransfer internal         a1:perp      -300.000000 USDC  <-> a1:spot
    lu:1782864180000:03030303030303030303030303030303:subAccountTransfer internal         a1:perp      -100.000000 USDC  <-> b2:perp
    lu:1782864240000:04040404040404040404040404040404:internalTransfer transfer_in      a1:perp        25.500000 USDC  <-> external
    lu:1782864300000:05050505050505050505050505050505:send internal         a1:spot       -50.000000 USDC  <-> a1:perp
    lu:1782864360000:06060606060606060606060606060606:spotTransfer transfer_out     a1:spot      -1.00000000 HYPE  <-> external
    lu:1782864360000:06060606060606060606060606060606:spotTransfer:fee trade_fee        a1:spot        -1.000000 USDC  <-> trading_fees
    lu:1782864420000:07070707070707070707070707070707:cStakingTransfer staking          a1:spot      -2.50000000 HYPE  <-> a1:staking
    lu:1782864480000:08080808080808080808080808080808:vaultDeposit vault_deposit    a1:perp      -100.000000 USDC  <-> vaults
    lu:1782864540000:09090909090909090909090909090909:vaultWithdraw vault_withdrawal a1:perp       104.000000 USDC  <-> vaults
    lu:1782864600000:0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a:vaultDistribution vault_commission a1:perp         3.250000 USDC  <-> vault_commission
    lu:1782864660000:0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b:gossipPriorityGasAuction trade_fee        a1:spot      -0.01000000 HYPE  <-> trading_fees
    lu:1782864720000:0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c:withdraw withdrawal       a1:perp       -99.000000 USDC  <-> bridge
    lu:1782864720000:0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c:withdraw:fee trade_fee        a1:perp        -1.000000 USDC  <-> trading_fees
    lu:1782864900000:0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f:rewardsClaim referral_reward  a1:perp        12.500000 USDC  <-> referral_rewards
    |}]
;;

let other_events () =
  let fills =
    match read "fills.json" with
    | `List items ->
      List.map items ~f:(fun j ->
        Hl.Adapter.Fill (Hl_protocol.User_fill.Detailed.t_of_yojson j))
    | _ -> assert false
  in
  let funding =
    Hl.Funding.list_of_yojson (read "funding.json")
    |> ok_exn
    |> List.map ~f:(fun f -> Hl.Adapter.Funding f)
  in
  let rewards =
    Hl.Staking_reward.list_of_yojson (read "staking_rewards.json")
    |> ok_exn
    |> List.map ~f:(fun r -> Hl.Adapter.Staking_reward r)
  in
  fills @ funding @ rewards
;;

let%expect_test "fills, funding and staking rewards" =
  show (Normalizer.normalize_all (module Hl.Adapter) config (other_events ()) |> ok_exn);
  [%expect
    {|
    fill fill:900001 perp:BTC Buy 0.02 @ 60000
    fill:900001:fee                              trade_fee        a1:perp        -0.420000 USDC  <-> trading_fees
    fill:900001:builder                          builder_fee      a1:perp        -0.120000 USDC  <-> builder_fees
    fill fill:900002 perp:BTC Sell 0.01 @ 61000
    fill:900002:pnl                              trade            a1:perp        10.000000 USDC  <-> perp_pnl
    fill:900002:fee                              trade_fee        a1:perp        -0.274500 USDC  <-> trading_fees
    fill fill:900003 spot:HYPE/USDC Buy 2 @ 40
    fill:900003:base                             trade            a1:spot       2.00000000 HYPE  <-> spot_clearing
    fill:900003:quote                            trade            a1:spot       -80.000000 USDC  <-> spot_clearing
    fill:900003:fee                              trade_fee        a1:spot      -0.00080000 HYPE  <-> trading_fees
    funding:1782867600000:BTC                    funding          a1:perp        -0.026051 USDC  <-> funding
    funding:1782867600000:xyz:GOLD               funding          a1:perp:xyz      0.123457 USDC  <-> funding
    stakingReward:1782950400012:delegation       staking_reward   a1:staking    0.00605586 HYPE  <-> staking_rewards
    |}]
;;

let report () : Hl.Adapter.report =
  { perp =
      [ ( None
        , Hl_protocol.Clearinghouse_state.t_of_yojson (read "clearinghouse_state.json") )
      ]
  ; spot = Some (Hl.Spot_state.of_yojson (read "spot_state.json") |> ok_exn)
  ; staking =
      Some (Hl.Delegator_summary.of_yojson (read "delegator_summary.json") |> ok_exn)
  ; observed_at = Hl.Adapter.time_of_ms 1782950400000
  }
;;

let%expect_test "observed balances and positions" =
  let observed = Hl.Adapter.observe config (report ()) |> ok_exn in
  List.iter observed.balances ~f:(fun b ->
    printf "%-12s %s\n" (short_location b.location) (Money.Amount.to_string b.amount));
  List.iter observed.positions ~f:(fun p ->
    printf
      "%s %s entry %s\n"
      (Instrument.to_string p.instrument)
      (Exact.to_string p.size)
      (Option.value_map p.entry_price ~default:"-" ~f:Exact.to_string));
  [%expect
    {|
    a1:perp      1045.300000 USDC
    a1:spot      170.000000 USDC
    a1:spot      10.48920000 HYPE
    a1:staking   2.50605586 HYPE
    perp:BTC 0.01 entry 60000
    |}]
;;

let%expect_test "end to end: books, openings, reconciliation and value" =
  let events =
    List.map (ledger_updates ()) ~f:(fun u -> Hl.Adapter.Ledger_update u)
    @ other_events ()
  in
  let items = Normalizer.normalize_all (module Hl.Adapter) config events |> ok_exn in
  let chart = Chart.create (Binding_id.of_string "treasury") in
  let at = Hl.Adapter.time_of_ms 1782950400000 in
  let books, ingested = Books.ingest (Books.create chart) items ~at |> ok_exn in
  printf
    "booked %d, skipped %d, fills %d\n"
    (List.length ingested.booked)
    (List.length ingested.skipped)
    (List.length ingested.realised);
  let observed = Hl.Adapter.observe config (report ()) |> ok_exn in
  let books, openings =
    Books.open_balances
      books
      observed
      ~history_start:(Hl.Adapter.time_of_ms 1782864000000)
      ~at
    |> ok_exn
  in
  List.iter openings ~f:(fun o ->
    printf
      "opening %-12s %s\n"
      (short_location o.location)
      (Money.Amount.to_string o.difference));
  let tolerance c = Money.Amount.of_minor_units_int c 1 in
  List.iter
    (Reconciliation.breaks (Books.reconcile ~tolerance books observed))
    ~f:(fun r ->
      printf
        "break %-12s %s %s\n"
        (short_location r.location)
        (Money.Currency.to_string r.asset)
        (Sexp.to_string [%sexp (r.status : Reconciliation.Status.t)]));
  List.iter (Books.reconcile_positions books observed) ~f:(fun r ->
    print_s [%sexp (r : Reconciliation.Position_row.t)]);
  Ledger.Trial_balance.check (Ledger.Trial_balance.of_balances (Books.balances books))
  |> ok_exn;
  [%expect
    {|
    booked 25, skipped 0, fills 3
    opening a1:perp      440.890551 USDC
    opening a1:spot      1.000000 USDC
    opening a1:spot      12.00000000 HYPE
    opening a1:staking   0.00000000 HYPE
    break a1:perp:xyz  USDC Not_reported
    break b2:perp      USDC Not_reported
    ((address 0x00000000000000000000000000000000000000a1)
     (instrument (Perp (coin BTC) (settle USDC))) (tracked 0.01) (observed 0.01)
     (matched true))
    |}]
;;

let%expect_test "a transfer between two bound addresses is the same activity from either \
                 side"
  =
  let update =
    List.find_exn (ledger_updates ()) ~f:(fun u ->
      String.equal (Hl.Ledger_update.Delta.type_name u.delta) "subAccountTransfer")
  in
  let from_b2 = Hl.Config.create b2 ~binding:[ a1 ] in
  let a = Hl.Adapter.normalize config (Ledger_update update) |> ok_exn in
  let b = Hl.Adapter.normalize from_b2 (Ledger_update update) |> ok_exn in
  print_s [%sexp (List.equal Normalized.equal a b : bool)];
  [%expect {| true |}]
;;

let%expect_test "unknown spot pairs and tokens are dropped, malformed records are errors" =
  let unknown_pair =
    Hl_protocol.User_fill.Detailed.t_of_yojson
      (`Assoc
        [ "coin", `String "@999"
        ; "px", `String "1.0"
        ; "sz", `String "1.0"
        ; "side", `String "B"
        ; "time", `Int 1782864000000
        ; "startPosition", `String "0.0"
        ; "dir", `String "Buy"
        ; "closedPnl", `String "0.0"
        ; "hash", `String "0x00"
        ; "oid", `Int 1
        ; "crossed", `Bool true
        ; "fee", `String "0.0"
        ; "tid", `Int 5
        ])
  in
  print_s
    [%sexp
      (Hl.Adapter.normalize config (Fill unknown_pair) |> ok_exn : Normalized.t list)];
  [%expect {| () |}];
  print_s
    [%sexp
      (Hl.Ledger_update.of_yojson
         (`Assoc
           [ "time", `Int 1
           ; "hash", `String "0x"
           ; "delta", `Assoc [ "type", `String "deposit" ]
           ])
       |> Or_error.map ~f:ignore
       : unit Or_error.t)];
  [%expect {| (Error ("decoding ledger update" (Failure "field usdc: missing"))) |}]
;;
