(** Small JSON reading helpers shared by the decoders. Every reader raises
    [Failure] with the field name on a missing or malformed field; the decoders turn that
    into an [Or_error]. *)

open! Core

(** [field json name] is the member [name] of an object. *)
val field : Yojson.Safe.t -> string -> Yojson.Safe.t

val field_opt : Yojson.Safe.t -> string -> Yojson.Safe.t option
val string : Yojson.Safe.t -> string -> string
val int : Yojson.Safe.t -> string -> int
val bool : Yojson.Safe.t -> string -> bool

(** A decimal string field (["-0.026051"], ["5472272.8957780004"]) as an exact number;
    a JSON number is accepted too. *)
val decimal : Yojson.Safe.t -> string -> Q.t

(** [decimal] for an optional or [null] field, zero when absent. *)
val decimal_or_zero : Yojson.Safe.t -> string -> Q.t

(** An address field, lowercased. *)
val address : Yojson.Safe.t -> string -> Hl_protocol.Address.t

(** Runs a decoder, turning its exceptions into an error tagged with [what]. *)
val decode : what:string -> (Yojson.Safe.t -> 'a) -> Yojson.Safe.t -> 'a Or_error.t

(** [Q.t] from a fixed-point value: [units / units_per_one]. *)
val q_of_fixed : units:int -> units_per_one:int -> Q.t
