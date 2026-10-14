(** The two-step record of a write to the chain (a send, a transfer between venues, a
    withdrawal, an order), so that a retry never signs twice.

    + Prepare: pick a nonce with {!next_nonce}, sign, and store the record with the exact
      request body ({!prepare}) before anything is sent.
    + Submit the stored body and apply what came back: [Accepted], [Rejected], or
      [Outcome_unknown] when the venue could not be reached or answered with a throttling
      or server error.
    + After an unknown outcome, resend the {e same} body ({!body_to_send}) when {!due}:
      the nonce makes a duplicate harmless, while a newly signed body could execute twice.
      Delays double from [base] up to [cap].
    + A sync that sees the movement on chain (an activity whose client key is this
      record's) applies [Seen_on_chain], which confirms it from any open state.

    {v
    signed --accepted--> accepted --seen--> confirmed
    signed --rejected--> rejected                    (the caller reverses its booking)
    signed --unknown---> retrying --accepted/rejected--> as above
                         retrying --unknown--> retrying | unconfirmed (attempts used up)
    any open state --rejected nonce_used--> unconfirmed
    v}

    [Unconfirmed] is never reversed automatically: an earlier attempt may have landed (a
    reused nonce says the venue has seen it), so a person or a later sync decides. *)

open! Core

(** Why the venue refused a write. *)
module Reject_reason : sig
  type t =
    | Insufficient_balance
    | Nonce_used
    | Signer_not_authorised
    | Invalid
    | Refused of string (** any other refusal, with the venue's message *)
  [@@deriving sexp, compare, equal]
end

(** Where a write stands. *)
module Status : sig
  type t =
    | Signed (** stored, not yet answered *)
    | Accepted of { reference : string option }
    | Confirmed
    | Rejected of Reject_reason.t
    | Retrying
    | Unconfirmed
  [@@deriving sexp, compare, equal]

  (** [Confirmed], [Rejected] and [Unconfirmed]. *)
  val is_final : t -> bool
end

(** When to resend after an unknown outcome. *)
module Retry_policy : sig
  type t =
    { base : Time_ns.Span.t
    ; cap : Time_ns.Span.t
    ; max_attempts : int (** submissions, the first included *)
    }
  [@@deriving sexp, compare, equal]

  (** 15 seconds doubling to 30 minutes, 10 attempts. *)
  val default : t

  (** The wait after the [attempt]-th submission ended without an answer: [base] times
      [2 ^ (attempt - 1)], at most [cap]. *)
  val delay : t -> attempt:int -> Time_ns.Span.t
end

(** What happened to a write: an answer to a submission, or a sync that saw it. *)
module Event : sig
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
end

type t = private
  { client_key : string (** the writer's idempotency key *)
  ; signer : string
  ; nonce : int (** milliseconds, unique per signer *)
  ; body : string (** the exact signed request, sent unchanged on every attempt *)
  ; status : Status.t
  ; attempts : int (** submissions answered or failed so far *)
  ; next_attempt_at : Time_ns.Alternate_sexp.t option (** set while [Retrying] *)
  ; updated_at : Time_ns.Alternate_sexp.t
  }
[@@deriving sexp, compare, equal]

(** [max (now in milliseconds) (last + 1)]: increasing per signer even when the clock
    steps back or two writes share a millisecond. *)
val next_nonce : now:Time_ns.t -> last:int option -> int

(** A [Signed] record. Fails on an empty client key, signer or body. *)
val prepare
  :  client_key:string
  -> signer:string
  -> nonce:int
  -> body:string
  -> at:Time_ns.t
  -> t Or_error.t

(** Applies an answer or an observation. Fails on an event the status does not accept (an
    answer to a final record, a second acceptance). *)
val apply : ?policy:Retry_policy.t -> t -> Event.t -> t Or_error.t

(** Whether the body should be sent now: [Signed] (the first attempt), or [Retrying] and
    its time has come. *)
val due : t -> now:Time_ns.t -> bool

(** The stored body when {!due}; an error otherwise. *)
val body_to_send : t -> now:Time_ns.t -> string Or_error.t

(** [Rejected]: nothing reached the chain, so whatever the caller booked for the write (a
    debit to an in-transit account) must be reversed. *)
val needs_reversal : t -> bool

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
