(** Validated string identifiers with a length cap and an allowed character set, shared by
    {!Binding_id}, {!Address} and {!Event_id}. *)

open! Core

(** What an id module exposes. *)
module type S = sig
  (** A checked id. *)
  type t [@@deriving quickcheck]

  include Identifiable.S with type t := t

  (** [of_string] raises on an invalid id; this is the non-raising form. *)
  val of_string_or_error : string -> t Or_error.t

  (** The longest accepted id, in bytes. *)
  val max_length : int

  module Stable : sig
    module V1 : sig
      (** Bin_prot is the plain string; decoding validates again. *)
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
    end
  end
end

(** [Make] builds an id type accepting 1 to [max_length] characters for which
    [allowed_char] holds. *)
module Make (_ : sig
    (** Used in error messages, e.g. ["Chain_books.Event_id"]. *)
    val module_name : string

    (** The longest id accepted. *)
    val max_length : int
    (** Whether a character may appear in an id. *)
    val allowed_char : char -> bool

    (** Characters the quickcheck generator draws from. *)
    val sample_chars : string
  end) : S
