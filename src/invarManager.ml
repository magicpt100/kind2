(* This file is part of the Kind 2 model checker.

   Copyright (c) 2014 by the Board of Trustees of the University of Iowa

   Licensed under the Apache License, Version 2.0 (the "License"); you
   may not use this file except in compliance with the License.  You
   may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0 

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
   implied. See the License for the specific language governing
   permissions and limitations under the License. 

*)
        
open Lib

let pp_print_hline ppf = 
  
  Format.fprintf 
    ppf 
    "------------------------------------------------------------------------"
    

let on_exit trans_sys =
  
  Event.log
    L_info
    "@[<v>%t@,\
     Final statistics:@]"
    pp_print_hline;
  
  List.iter 
    (fun (mdl, stat) -> Event.log_stat mdl L_info stat)
    (Event.all_stats ());
  
  Event.log
    L_fatal
    "@[<v>%t@,\
     Summary of properties:@]"
    pp_print_hline;
  
  (match trans_sys with | None -> () | Some trans_sys ->
    Event.log_prop_status L_fatal (TransSys.prop_status_all trans_sys));
    
  Event.log
    L_warn 
    "";
  
  try 
    
    (* Send termination message to all worker processes *)
    Event.terminate ();

  (* Skip if running as a single process *)
  with Messaging.NotInitialized -> ()


(* Remove terminated child processed from list of running processes

   Return [true] if the last child processes has terminated or some
   process exited with a runtime error or was killed. *)
let rec wait_for_children child_pids = 

  match 
    
    (try 

       (* Check if any child process has died, return immediately *)
       Unix.waitpid [Unix.WNOHANG] (- 1) 

     (* Catch error if there is no child process *)
     with Unix.Unix_error (Unix.ECHILD, _, _) -> 0, Unix.WEXITED 0)

  with 

    (* No child process died *)
    | 0, _ -> 

      (* Terminate if the last child process has died *)
      !child_pids = []

    (* Child process exited normally *)
    | child_pid, (Unix.WEXITED 0 as status) -> 

      (

        Event.log L_info
          "Child process %d (%a) %a" 
          child_pid 
          pp_print_kind_module (List.assoc child_pid !child_pids) 
          pp_print_process_status status;

        (* Remove child process from list *)
        child_pids := List.remove_assoc child_pid !child_pids;

        (* Check if more child processes have died *)
        wait_for_children child_pids

      )

    (* Child process dies with non-zero exit status or was killed *)
    | child_pid, status -> 

      (Event.log L_error
         "Child process %d (%a) %a" 
         child_pid 
         pp_print_kind_module (List.assoc child_pid !child_pids) 
         pp_print_process_status status;

       (* Remove child process from list *)
       child_pids := List.remove_assoc child_pid !child_pids;

       (* Check if more child processes have died *)
       true

      )


let handle_events trans_sys = 

  (* Receive queued events *)
  let events = Event.recv () in

  (* Output events *)
  List.iter 
    (function (m, e) -> 
      Event.log
        L_debug
        "Message received from %a: %a"
        pp_print_kind_module m
        Event.pp_print_event e)
    events;

  (* Update transition system from events *)
  let _, prop_status =
    Event.update_trans_sys trans_sys events
  in

  (* Output proved properties *)
  List.iter

    (function 

      (* No output for unknown or k-true properties *)
      | (_, (_, TransSys.PropUnknown))
      | (_, (_, TransSys.PropKTrue _)) -> ()

      | (m, (p, TransSys.PropInvariant)) -> 
        Event.log_proved m L_warn None p

      | (m, (p, TransSys.PropFalse cex)) -> 
        Event.log_disproved m L_warn trans_sys p cex)

    prop_status


(* Polling loop *)
let rec loop child_pids trans_sys = 

  handle_events trans_sys;

  (* All properties proved? *)
  if TransSys.all_props_proved trans_sys then 
    
    ( 
      
      Event.log L_info "All properties proved or disproved";
      
      Event.terminate ()
        
    );


  (* Check if child processes have died and exit if necessary *)
  if wait_for_children child_pids then 

    (
      
      (* Get messages after termination of all processes *)
      handle_events trans_sys

    )
    
  else 

    (

      (* Sleep *)
      minisleep 0.01;

      (* Continue polling loop *)
      loop child_pids trans_sys

    )
  

(* Entry point *)
let main child_pids transSys =

  (* Run main loop *)
  loop child_pids transSys

(* 
   Local Variables:
   compile-command: "make -C .. -k"
   tuareg-interactive-program: "./kind2.top -I ./_build -I ./_build/SExpr"
   indent-tabs-mode: nil
   End: 
*)
  
