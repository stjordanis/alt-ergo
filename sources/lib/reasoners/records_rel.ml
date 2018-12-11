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

module Relation (X : Records.ALIEN) (Uf : Uf.S) = struct
  type r = X.r
  type uf = Uf.t
  type t = unit

  let empty _ = ()
  let assume _ _ _ =
    (), { Sig_rel.assume = []; remove = []}
  let query _ _ _ = Sig_rel.No
  let case_split env _ ~for_model = []
  let add env _ _ _ = env
  let print_model _ _ _ = ()
  let new_terms env = Expr.Set.empty
  let instantiate ~do_syntactic_matching _ env uf _ = env, []

  let assume_th_elt t th_elt dep =
    match th_elt.Expr.extends with
    | Util.Records ->
      failwith "This Theory does not support theories extension"
    | _ -> t

end
