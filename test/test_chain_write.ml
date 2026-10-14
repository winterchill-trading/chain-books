open! Core
open Chain_books
open Helpers

let prepared () =
  Chain_write.prepare
    ~client_key:"payout:7"
    ~signer:"0xa1"
    ~nonce:(Chain_write.next_nonce ~now:t0 ~last:None)
    ~body:{|{"action":{"type":"usdSend"},"nonce":1782864000000}|}
    ~at:t0
  |> Or_error.ok_exn
;;

let step w event =
  let w = Chain_write.apply w event |> Or_error.ok_exn in
  print_s
    [%message
      ""
        ~status:(w.status : Chain_write.Status.t)
        ~attempts:(w.attempts : int)
        ~next:(w.next_attempt_at : Time_ns.Alternate_sexp.t option)];
  w
;;

let%expect_test "unknown outcomes resend the same body with doubling delays" =
  let w = prepared () in
  print_s [%sexp (w.nonce : int), (Chain_write.due w ~now:t0 : bool)];
  [%expect {| (1782864000000 true) |}];
  let w = step w (Outcome_unknown { at = t0 }) in
  [%expect {| ((status Retrying) (attempts 1) (next ("2026-07-01 00:00:15Z"))) |}];
  print_s [%sexp (Chain_write.body_to_send w ~now:(at_min 0) : string Or_error.t)];
  [%expect
    {| (Error ("chain write is not due" (client_key payout:7) (status Retrying))) |}];
  let w = step w (Outcome_unknown { at = at_min 1 }) in
  [%expect {| ((status Retrying) (attempts 2) (next ("2026-07-01 00:01:30Z"))) |}];
  print_s [%sexp (Chain_write.body_to_send w ~now:(at_min 2) : string Or_error.t)];
  [%expect {| (Ok "{\"action\":{\"type\":\"usdSend\"},\"nonce\":1782864000000}") |}];
  let w = step w (Accepted { reference = Some "0xhash"; at = at_min 2 }) in
  [%expect {| ((status (Accepted (reference (0xhash)))) (attempts 3) (next ())) |}];
  let w = step w (Seen_on_chain { at = at_min 5 }) in
  [%expect {| ((status Confirmed) (attempts 3) (next ())) |}];
  print_s
    [%sexp
      (Chain_write.apply w (Accepted { reference = None; at = at_min 6 })
       |> Or_error.map ~f:ignore
       : unit Or_error.t)];
  [%expect
    {|
    (Error
     ("chain write cannot take this event" (client_key payout:7)
      (status Confirmed)
      (event (Accepted (reference ()) (at "2026-07-01 00:06:00Z")))))
    |}]
;;

let%expect_test "a refusal needs a reversal; a reused nonce does not" =
  let rejected = step (prepared ()) (Rejected { reason = Insufficient_balance; at = t0 }) in
  let reused = step (prepared ()) (Rejected { reason = Nonce_used; at = t0 }) in
  print_s
    [%sexp
      (Chain_write.needs_reversal rejected : bool), (Chain_write.needs_reversal reused : bool)];
  [%expect
    {|
    ((status (Rejected Insufficient_balance)) (attempts 1) (next ()))
    ((status Unconfirmed) (attempts 1) (next ()))
    (true false)
    |}]
;;

let%expect_test "attempts run out into unconfirmed" =
  let policy = { Chain_write.Retry_policy.default with max_attempts = 2 } in
  let w = prepared () in
  let w = Chain_write.apply ~policy w (Outcome_unknown { at = t0 }) |> Or_error.ok_exn in
  let w = Chain_write.apply ~policy w (Outcome_unknown { at = at_min 1 }) |> Or_error.ok_exn in
  print_s [%sexp (w.status : Chain_write.Status.t), (Chain_write.due w ~now:(at_min 60) : bool)];
  [%expect {| (Unconfirmed false) |}]
;;

let%test_unit "delays never pass the cap and never shrink" =
  let policy = Chain_write.Retry_policy.default in
  Quickcheck.test (Int.gen_incl 1 10_000) ~f:(fun attempt ->
    let d = Chain_write.Retry_policy.delay policy ~attempt in
    let next = Chain_write.Retry_policy.delay policy ~attempt:(attempt + 1) in
    assert (Time_ns.Span.( <= ) d policy.cap);
    assert (Time_ns.Span.( <= ) d next))
;;

let%test_unit "nonces increase per signer whatever the clock does" =
  Quickcheck.test
    (List.quickcheck_generator (Int.gen_incl (-5_000) 5_000))
    ~f:(fun jumps ->
      ignore
        (List.fold jumps ~init:(t0, None) ~f:(fun (now, last) jump_ms ->
           let now = Time_ns.add now (Time_ns.Span.of_int_ms jump_ms) in
           let nonce = Chain_write.next_nonce ~now ~last in
           Option.iter last ~f:(fun last -> assert (nonce > last));
           now, Some nonce)
         : Time_ns.t * int option))
;;

let gen_event =
  let open Quickcheck.Generator.Let_syntax in
  let%bind minute = Int.gen_incl 0 100 in
  let at = at_min minute in
  Quickcheck.Generator.of_list
    [ Chain_write.Event.Accepted { reference = None; at }
    ; Rejected { reason = Invalid; at }
    ; Rejected { reason = Nonce_used; at }
    ; Outcome_unknown { at }
    ; Outcome_unknown { at }
    ; Outcome_unknown { at }
    ; Seen_on_chain { at }
    ]
;;

let%test_unit "the body never changes and final states take no answers" =
  Quickcheck.test (List.quickcheck_generator gen_event) ~f:(fun events ->
    let start = prepared () in
    ignore
      (List.fold events ~init:start ~f:(fun w event ->
         match Chain_write.apply w event with
         | Error _ ->
           (* Open states that wait for an answer accept every event. *)
           (match w.status with
            | Signed | Retrying -> assert false
            | Accepted _ | Confirmed | Rejected _ | Unconfirmed -> ());
           w
         | Ok next ->
           [%test_result: string] next.body ~expect:start.body;
           [%test_result: int] next.nonce ~expect:start.nonce;
           assert (next.attempts >= w.attempts);
           next)
       : Chain_write.t))
;;
