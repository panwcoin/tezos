(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2018.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

type peer_id = Crypto_box.Public_key_hash.t
let peer_id_encoding = Crypto_box.Public_key_hash.encoding
let peer_id_pp = Crypto_box.Public_key_hash.pp

module Id = struct

  (* A net point (address x port). *)
  type t = P2p_addr.t * P2p_addr.port option
  let compare (a1, p1) (a2, p2) =
    match Ipaddr.V6.compare a1 a2 with
    | 0 -> Pervasives.compare p1 p2
    | x -> x
  let equal p1 p2 = compare p1 p2 = 0
  let hash = Hashtbl.hash
  let pp ppf (addr, port) =
    match port with
    | None ->
        Format.fprintf ppf "[%a]:??" Ipaddr.V6.pp_hum addr
    | Some port ->
        Format.fprintf ppf "[%a]:%d" Ipaddr.V6.pp_hum addr port
  let pp_opt ppf = function
    | None -> Format.pp_print_string ppf "none"
    | Some point -> pp ppf point
  let to_string t = Format.asprintf "%a" pp t

  let is_local (addr, _) = Ipaddr.V6.is_private addr
  let is_global (addr, _) = not @@ Ipaddr.V6.is_private addr

  let of_point (addr, port) = addr, Some port
  let to_point = function
    | _, None -> None
    | addr, Some port -> Some (addr, port)
  let to_point_exn = function
    | _, None -> invalid_arg "to_point_exn"
    | addr, Some port -> addr, port

  let encoding =
    let open Data_encoding in
    (obj2
       (req "addr" P2p_addr.encoding)
       (opt "port" uint16))

end

module Map = Map.Make (Id)
module Set = Set.Make (Id)
module Table = Hashtbl.Make (Id)

module Info = struct

  type t = {
    incoming : bool;
    peer_id : peer_id;
    id_point : Id.t;
    remote_socket_port : P2p_addr.port;
    versions : P2p_version.t list ;
  }

  let encoding =
    let open Data_encoding in
    conv
      (fun { incoming ; peer_id ; id_point ; remote_socket_port ; versions } ->
         (incoming, peer_id, id_point, remote_socket_port, versions))
      (fun (incoming, peer_id, id_point, remote_socket_port, versions) ->
         { incoming ; peer_id ; id_point ; remote_socket_port ; versions })
      (obj5
         (req "incoming" bool)
         (req "peer_id" peer_id_encoding)
         (req "id_point" Id.encoding)
         (req "remote_socket_port" uint16)
         (req "versions" (list P2p_version.encoding)))

  let pp ppf
      { incoming ; id_point = (remote_addr, remote_port) ;
        remote_socket_port ; peer_id ; versions } =
    let version = List.hd versions in
    let point = match remote_port with
      | None -> remote_addr, remote_socket_port
      | Some port -> remote_addr, port in
    Format.fprintf ppf "%s %a %a (%a)"
      (if incoming then "↘" else "↗")
      peer_id_pp peer_id
      P2p_point.Id.pp point
      P2p_version.pp version

end

module Pool_event = struct

  (** Pool-level events *)

  type t =

    | Too_few_connections
    | Too_many_connections

    | New_point of P2p_point.Id.t
    | New_peer of peer_id

    | Gc_points
    | Gc_peer_ids

    | Incoming_connection of P2p_point.Id.t
    | Outgoing_connection of P2p_point.Id.t
    | Authentication_failed of P2p_point.Id.t
    | Accepting_request of P2p_point.Id.t * Id.t * peer_id
    | Rejecting_request of P2p_point.Id.t * Id.t * peer_id
    | Request_rejected of P2p_point.Id.t * (Id.t * peer_id) option
    | Connection_established of Id.t * peer_id

    | Swap_request_received of { source : peer_id }
    | Swap_ack_received of { source : peer_id }
    | Swap_request_sent of { source : peer_id }
    | Swap_ack_sent of { source : peer_id }
    | Swap_request_ignored of { source : peer_id }
    | Swap_success of { source : peer_id }
    | Swap_failure of { source : peer_id }

    | Disconnection of peer_id
    | External_disconnection of peer_id

  let encoding =
    let open Data_encoding in
    let branch_encoding name obj =
      conv (fun x -> (), x) (fun ((), x) -> x)
        (merge_objs
           (obj1 (req "event" (constant name))) obj) in
    union ~tag_size:`Uint8 [
      case (Tag 0) (branch_encoding "too_few_connections" empty)
        (function Too_few_connections -> Some () | _ -> None)
        (fun () -> Too_few_connections) ;
      case (Tag 1) (branch_encoding "too_many_connections" empty)
        (function Too_many_connections -> Some () | _ -> None)
        (fun () -> Too_many_connections) ;
      case (Tag 2) (branch_encoding "new_point"
                      (obj1 (req "point" P2p_point.Id.encoding)))
        (function New_point p -> Some p | _ -> None)
        (fun p -> New_point p) ;
      case (Tag 3) (branch_encoding "new_peer"
                      (obj1 (req "peer_id" peer_id_encoding)))
        (function New_peer p -> Some p | _ -> None)
        (fun p -> New_peer p) ;
      case (Tag 4) (branch_encoding "incoming_connection"
                      (obj1 (req "point" P2p_point.Id.encoding)))
        (function Incoming_connection p -> Some p | _ -> None)
        (fun p -> Incoming_connection p) ;
      case (Tag 5) (branch_encoding "outgoing_connection"
                      (obj1 (req "point" P2p_point.Id.encoding)))
        (function Outgoing_connection p -> Some p | _ -> None)
        (fun p -> Outgoing_connection p) ;
      case (Tag 6) (branch_encoding "authentication_failed"
                      (obj1 (req "point" P2p_point.Id.encoding)))
        (function Authentication_failed p -> Some p | _ -> None)
        (fun p -> Authentication_failed p) ;
      case (Tag 7) (branch_encoding "accepting_request"
                      (obj3
                         (req "point" P2p_point.Id.encoding)
                         (req "id_point" Id.encoding)
                         (req "peer_id" peer_id_encoding)))
        (function Accepting_request (p, id_p, g) ->
           Some (p, id_p, g) | _ -> None)
        (fun (p, id_p, g) -> Accepting_request (p, id_p, g)) ;
      case (Tag 8) (branch_encoding "rejecting_request"
                      (obj3
                         (req "point" P2p_point.Id.encoding)
                         (req "id_point" Id.encoding)
                         (req "peer_id" peer_id_encoding)))
        (function Rejecting_request (p, id_p, g) ->
           Some (p, id_p, g) | _ -> None)
        (fun (p, id_p, g) -> Rejecting_request (p, id_p, g)) ;
      case (Tag 9) (branch_encoding "request_rejected"
                      (obj2
                         (req "point" P2p_point.Id.encoding)
                         (opt "identity"
                            (tup2 Id.encoding peer_id_encoding))))
        (function Request_rejected (p, id) -> Some (p, id) | _ -> None)
        (fun (p, id) -> Request_rejected (p, id)) ;
      case (Tag 10) (branch_encoding "connection_established"
                       (obj2
                          (req "id_point" Id.encoding)
                          (req "peer_id" peer_id_encoding)))
        (function Connection_established (id_p, g) ->
           Some (id_p, g) | _ -> None)
        (fun (id_p, g) -> Connection_established (id_p, g)) ;
      case (Tag 11) (branch_encoding "disconnection"
                       (obj1 (req "peer_id" peer_id_encoding)))
        (function Disconnection g -> Some g | _ -> None)
        (fun g -> Disconnection g) ;
      case (Tag 12) (branch_encoding "external_disconnection"
                       (obj1 (req "peer_id" peer_id_encoding)))
        (function External_disconnection g -> Some g | _ -> None)
        (fun g -> External_disconnection g) ;
      case (Tag 13) (branch_encoding "gc_points" empty)
        (function Gc_points -> Some () | _ -> None)
        (fun () -> Gc_points) ;
      case (Tag 14) (branch_encoding "gc_peer_ids" empty)
        (function Gc_peer_ids -> Some () | _ -> None)
        (fun () -> Gc_peer_ids) ;
      case (Tag 15) (branch_encoding "swap_request_received"
                       (obj1 (req "source" peer_id_encoding)))
        (function
          | Swap_request_received { source } -> Some source
          | _ -> None)
        (fun source -> Swap_request_received { source }) ;
      case (Tag 16) (branch_encoding "swap_ack_received"
                       (obj1 (req "source" peer_id_encoding)))
        (function
          | Swap_ack_received { source } -> Some source
          | _ -> None)
        (fun source -> Swap_ack_received { source }) ;
      case (Tag 17) (branch_encoding "swap_request_sent"
                       (obj1 (req "source" peer_id_encoding)))
        (function
          | Swap_request_sent { source } -> Some source
          | _ -> None)
        (fun source -> Swap_request_sent { source }) ;
      case (Tag 18) (branch_encoding "swap_ack_sent"
                       (obj1 (req "source" peer_id_encoding)))
        (function
          | Swap_ack_sent { source } -> Some source
          | _ -> None)
        (fun source -> Swap_ack_sent { source }) ;
      case (Tag 19) (branch_encoding "swap_request_ignored"
                       (obj1 (req "source" peer_id_encoding)))
        (function
          | Swap_request_ignored { source } -> Some source
          | _ -> None)
        (fun source -> Swap_request_ignored { source }) ;
      case (Tag 20) (branch_encoding "swap_success"
                       (obj1 (req "source" peer_id_encoding)))
        (function
          | Swap_success { source } -> Some source
          | _ -> None)
        (fun source -> Swap_success { source }) ;
      case (Tag 21) (branch_encoding "swap_failure"
                       (obj1 (req "source" peer_id_encoding)))
        (function
          | Swap_failure { source } -> Some source
          | _ -> None)
        (fun source -> Swap_failure { source }) ;
    ]

end
