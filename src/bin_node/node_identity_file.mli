(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2018.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

type error += No_identity_file of string
type error += Insufficient_proof_of_work of { expected: float }

val read:
  ?expected_pow:float ->
  string -> P2p_identity.t tzresult Lwt.t

type error += Existent_identity_file of string

val write: string -> P2p_identity.t -> unit tzresult Lwt.t
