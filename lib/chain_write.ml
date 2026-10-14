open! Core
module Time = Time_ns.Stable.Alternate_sexp.V1

module Reject_reason = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Insufficient_balance
        | Nonce_used
        | Signer_not_authorised
        | Invalid
        | Refused of string
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1
end

module Status = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Signed
        | Accepted of { reference : string option }
        | Confirmed
        | Rejected of Reject_reason.Stable.V1.t
        | Retrying
        | Unconfirmed
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1

  let is_final = function
    | Confirmed | Rejected _ | Unconfirmed -> true
    | Signed | Accepted _ | Retrying -> false
  ;;
end

module Retry_policy = struct
  type t =
    { base : Time_ns.Span.t
    ; cap : Time_ns.Span.t
    ; max_attempts : int
    }
  [@@deriving sexp, compare, equal]

  let default =
    { base = Time_ns.Span.of_int_sec 15
    ; cap = Time_ns.Span.of_int_min 30
    ; max_attempts = 10
    }
  ;;

  (* Doubles step by step and stops at the cap: [Span.scale] by [2 ** n] raises once n
     passes about 35, and shifting an int silently overflows. *)
  let delay t ~attempt =
    let rec go span n =
      if n <= 1 || Time_ns.Span.( >= ) span t.cap
      then Time_ns.Span.min span t.cap
      else go (Time_ns.Span.scale_int span 2) (n - 1)
    in
    go t.base attempt
  ;;
end

module Event = struct
  type t =
    | Accepted of
        { reference : string option
        ; at : Time_ns.Alternate_sexp.t
        }
    | Rejected of
        { reason : Reject_reason.t
        ; at : Time_ns.Alternate_sexp.t
        }
    | Outcome_unknown of { at : Time_ns.Alternate_sexp.t }
    | Seen_on_chain of { at : Time_ns.Alternate_sexp.t }
  [@@deriving sexp, compare, equal]

  let at = function
    | Accepted { at; _ }
    | Rejected { at; _ }
    | Outcome_unknown { at }
    | Seen_on_chain { at } -> at
  ;;
end

module Stable = struct
  module V1 = struct
    type t =
      { client_key : string
      ; signer : string
      ; nonce : int
      ; body : string
      ; status : Status.Stable.V1.t
      ; attempts : int
      ; next_attempt_at : Time.t option
      ; updated_at : Time.t
      }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

type t = Stable.V1.t =
  { client_key : string
  ; signer : string
  ; nonce : int
  ; body : string
  ; status : Status.t
  ; attempts : int
  ; next_attempt_at : Time_ns.Alternate_sexp.t option
  ; updated_at : Time_ns.Alternate_sexp.t
  }
[@@deriving sexp, compare, equal]

let next_nonce ~now ~last =
  let ms = Int63.to_int_exn (Time_ns.to_int63_ns_since_epoch now) / 1_000_000 in
  match last with
  | Some last -> Int.max ms (last + 1)
  | None -> ms
;;

let prepare ~client_key ~signer ~nonce ~body ~at =
  if String.is_empty client_key || String.is_empty signer || String.is_empty body
  then Or_error.error_s [%message "chain write needs a client key, a signer and a body"]
  else
    Ok
      { client_key
      ; signer
      ; nonce
      ; body
      ; status = Signed
      ; attempts = 0
      ; next_attempt_at = None
      ; updated_at = at
      }
;;

let apply ?(policy = Retry_policy.default) t (event : Event.t) =
  let at = Event.at event in
  let set ?(attempts = t.attempts) ?next_attempt_at status =
    Ok { t with status; attempts; next_attempt_at; updated_at = at }
  in
  let answered = t.attempts + 1 in
  let refuse () =
    Or_error.error_s
      [%message
        "chain write cannot take this event"
          ~client_key:t.client_key
          ~status:(t.status : Status.t)
          (event : Event.t)]
  in
  match t.status, event with
  | (Signed | Retrying), Accepted { reference; _ } ->
    set ~attempts:answered (Accepted { reference })
  | (Signed | Retrying), Rejected { reason = Nonce_used; _ } ->
    set ~attempts:answered Unconfirmed
  | (Signed | Retrying), Rejected { reason; _ } ->
    set ~attempts:answered (Rejected reason)
  | (Signed | Retrying), Outcome_unknown _ ->
    if answered >= policy.max_attempts
    then set ~attempts:answered Unconfirmed
    else
      set
        ~attempts:answered
        ~next_attempt_at:(Time_ns.add at (Retry_policy.delay policy ~attempt:answered))
        Retrying
  | (Signed | Retrying | Accepted _ | Unconfirmed), Seen_on_chain _ -> set Confirmed
  | Confirmed, Seen_on_chain _ -> Ok t
  | ( (Accepted _ | Confirmed | Rejected _ | Unconfirmed)
    , (Accepted _ | Rejected _ | Outcome_unknown _) )
  | Rejected _, Seen_on_chain _ -> refuse ()
;;

let due t ~now =
  match t.status, t.next_attempt_at with
  | Signed, _ -> true
  | Retrying, Some next -> Time_ns.( >= ) now next
  | Retrying, None -> true
  | (Accepted _ | Confirmed | Rejected _ | Unconfirmed), _ -> false
;;

let body_to_send t ~now =
  if due t ~now
  then Ok t.body
  else
    Or_error.error_s
      [%message
        "chain write is not due" ~client_key:t.client_key ~status:(t.status : Status.t)]
;;

let needs_reversal t =
  match t.status with
  | Rejected _ -> true
  | Signed | Accepted _ | Confirmed | Retrying | Unconfirmed -> false
;;
