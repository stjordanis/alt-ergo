(******************************************************************************)
(*                                                                            *)
(*     The Alt-Ergo theorem prover                                            *)
(*     Copyright (C) 2006-2013                                                *)
(*                                                                            *)
(*     Sylvain Conchon                                                        *)
(*     Evelyne Contejean                                                      *)
(*                                                                            *)
(*     Francois Bobot                                                         *)
(*     Mohamed Iguernelala                                                    *)
(*     Stephane Lescuyer                                                      *)
(*     Alain Mebsout                                                          *)
(*                                                                            *)
(*     CNRS - INRIA - Universite Paris Sud                                    *)
(*                                                                            *)
(*     This file is distributed under the terms of the Apache Software        *)
(*     License version 2.0                                                    *)
(*                                                                            *)
(*  ------------------------------------------------------------------------  *)
(*                                                                            *)
(*     Alt-Ergo: The SMT Solver For Software Verification                     *)
(*     Copyright (C) 2013-2018 --- OCamlPro SAS                               *)
(*                                                                            *)
(*     This file is distributed under the terms of the Apache Software        *)
(*     License version 2.0                                                    *)
(*                                                                            *)
(******************************************************************************)

open AltErgoLib
open Options
open Alt_ergo_common

(* workaround to force inclusion of main_input,
   because dune is stupid, :p *)
include Main_input

(* done here to initialize options,
   before the instantiations of functors *)
let () =
  try Parse_command.parse_cmdline_arguments ()
  with Parse_command.Exit_parse_command i -> exit i

module SatCont = (val (Sat_solver.get_current ()) : Sat_solver_sig.SatContainer)

module TH =
  (val
    (if Options.get_no_theory() then (module Theory.Main_Empty : Theory.S)
     else (module Theory.Main_Default : Theory.S)) : Theory.S )

module SAT = SatCont.Make(TH)

module FE = Frontend.Make (SAT)

let timers = Timers.empty ()

let () =
  (* what to do with Ctrl+C ? *)
  Sys.set_signal Sys.sigint(*-6*)
    (Sys.Signal_handle (fun _ ->
         if Options.get_profiling() then Profiling.switch ()
         else begin
           Format.eprintf "; User wants me to stop.\n";
           Format.printf "unknown@.";
           exit 1
         end
       )
    )

let () =
  (* put the test here because Windows does not handle Sys.Signal_handle
     correctly *)
  if Options.get_profiling() then
    List.iter
      (fun sign ->
         Sys.set_signal sign
           (Sys.Signal_handle
              (fun _ ->
                 Profiling.print true (Steps.get_steps ()) timers fmt;
                 exit 1
              )
           )
      )[ Sys.sigterm (*-11*); Sys.sigquit (*-9*)]

let () =
  (* put the test here because Windows does not handle Sys.Signal_handle
     correctly *)
  if Options.get_profiling() then
    Sys.set_signal Sys.sigprof (*-21*)
      (Sys.Signal_handle
         (fun _ ->
            Profiling.print false (Steps.get_steps ()) timers fmt;
         )
      )

let () =
  if not (get_model ()) then
    try
      Sys.set_signal Sys.sigvtalrm
        (Sys.Signal_handle (fun _ -> Options.exec_timeout ()))
    with Invalid_argument _ -> ()

let init_profiling () =
  if Options.get_profiling () then begin
    Timers.reset timers;
    assert (Options.get_timers());
    Timers.set_timer_start (Timers.start timers);
    Timers.set_timer_pause (Timers.pause timers);
    Profiling.init ();
  end

(* Internal state while iterating over input statements *)
type 'a state = {
  env : 'a;
  ctx   : Commands.sat_tdecl list;
  local : Commands.sat_tdecl list;
  global : Commands.sat_tdecl list;
}

let solve all_context (cnf, goal_name) =
  let used_context = FE.choose_used_context all_context ~goal_name in
  init_profiling ();
  try
    if Options.get_timelimit_per_goal() then
      begin
        Options.Time.start ();
        Options.Time.set_timeout ~is_gui:false (Options.get_timelimit ());
      end;
    SAT.reset_refs ();
    let _ =
      List.fold_left
        (FE.process_decl FE.print_status used_context)
        (SAT.empty (), true, Explanation.empty) cnf
    in
    if Options.get_timelimit_per_goal() then
      Options.Time.unset_timeout ~is_gui:false;
    if Options.get_profiling() then
      Profiling.print true (Steps.get_steps ()) timers fmt
  with Util.Timeout ->
    if not (Options.get_timelimit_per_goal()) then exit 142

let typed_loop all_context state td =
  if get_type_only () then state else begin
    match td.Typed.c with
    | Typed.TGoal (_, kind, name, _) ->
      let l = state.local @ state.global @ state.ctx in
      let cnf = List.rev @@ Cnf.make l td in
      let () = solve all_context (cnf, name) in
      begin match kind with
        | Typed.Check
        | Typed.Cut -> { state with local = []; }
        | _ -> { state with global = []; local = []; }
      end
    | Typed.TAxiom (_, s, _, _) when Typed.is_global_hyp s ->
      let cnf = Cnf.make state.global td in
      { state with global = cnf; }
    | Typed.TAxiom (_, s, _, _) when Typed.is_local_hyp s ->
      let cnf = Cnf.make state.local td in
      { state with local = cnf; }
    | _ ->
      let cnf = Cnf.make state.ctx td in
      { state with ctx = cnf; }
  end

let () =
  let (module I : Input.S) = Input.find (Options.get_frontend ()) in
  let parsed =
    try
      Options.Time.start ();
      if not (Options.get_timelimit_per_goal()) then
        Options.Time.set_timeout ~is_gui:false (Options.get_timelimit ());

      Options.set_is_gui false;
      init_profiling ();

      let filename = get_file () in
      let preludes = Options.get_preludes () in
      I.parse_files ~filename ~preludes
    with
    | Util.Timeout ->
      FE.print_status (FE.Timeout None) 0;
      exit 142
    | Parsing.Parse_error ->
      Errors.print_error Format.err_formatter
        (Syntax_error ((Lexing.dummy_pos,Lexing.dummy_pos),""));
      exit 1
    | Errors.Error e ->
      Errors.print_error Format.err_formatter e;
      exit 1

  in
  let all_used_context = FE.init_all_used_context () in
  if Options.get_timelimit_per_goal() then
    FE.print_status FE.Preprocess 0;
  let typing_loop state p =
    if get_parse_only () then state else begin
      try
        let l, env = I.type_parsed state.env p in
        List.fold_left (typed_loop all_used_context) { state with env; } l
      with
        Errors.Error e ->
        Errors.print_error Format.err_formatter e;
        exit 1
    end
  in
  let state = {
    env = I.empty_env;
    ctx = [];
    local = [];
    global = [];
  } in
  let _ : _ state = Seq.fold_left typing_loop state parsed in
  Options.Time.unset_timeout ~is_gui:false;

(*
  match d with
  | [] -> ()
  | [cnf, goal_name] ->
    begin
      let used_context = FE.choose_used_context all_used_context ~goal_name in
      try
        SAT.reset_refs ();
        ignore
          (List.fold_left (FE.process_decl FE.print_status used_context)
             (SAT.empty (), true, Explanation.empty) cnf);
        Options.Time.unset_timeout ~is_gui:false;
        if Options.get_profiling() then
          Profiling.print true (SAT.get_steps ()) timers fmt;
      with Util.Timeout -> ()
    end
  | _ ->
*)
