Require Export SfLib.

Require Export Arith.EqNat.

Require Export Arith.Le.

(* 
WIP: experiment with more layers of pushback / translation

especially, invertible bindx rule
*)


(* ############################################################ *)
(* Syntax *)
(* ############################################################ *)

Module DOT.

Definition id := nat.

Inductive ty : Type :=
  | TNoF   : ty (* marker for empty method list *)

  | TBot   : ty
  | TTop   : ty
  | TBool  : ty
  | TAnd   : ty -> ty -> ty
  | TFun   : id -> ty -> ty -> ty
  | TMem   : ty -> ty -> ty
  | TSel   : id -> ty

  | TSelB  : id -> ty
  | TBind  : ty -> ty
.
  
Inductive tm : Type :=
  | ttrue : tm
  | tfalse : tm
  | tvar : id -> tm
  | tapp : id -> id -> tm -> tm (* a.f(x) *)
  | tabs : id -> ty -> list (id * dc) -> tm -> tm (* let f:T = x => y in z *)
  | tlet : id -> ty -> tm -> tm -> tm (* let x:T = y *)                                         
with dc: Type :=
  | dfun : ty -> ty -> id -> tm -> dc (* def m:T = x => y *)
.

Fixpoint dc_type_and (dcs: list(nat*dc)) :=
  match dcs with
    | nil => TNoF
    | (n, dfun T1 T2 _ _)::dcs =>
      TAnd (TFun (length dcs) T1 T2)  (dc_type_and dcs)
  end.


Definition TObj p dcs := TAnd (TMem p p) (dc_type_and dcs).
Definition TArrow p x y := TAnd (TMem p p) (TAnd (TFun 0 x y) TNoF).


Inductive vl : Type :=
| vbool : bool -> vl
| vabs  : list (id*vl) -> id -> ty -> list (id * dc) -> vl (* clos env f:T = x => y *)
| vmock : list (id*vl) -> ty -> id -> id -> vl
.

Definition env := list (nat*vl).
Definition tenv := list (nat*ty).

Fixpoint index {X : Type} (n : nat)
               (l : list (nat * X)) : option X :=
  match l with
    | [] => None
    (* for now, ignore binding value n' !!! *)
    | (n',a) :: l'  => if beq_nat n (length l') then Some a else index n l'
  end.

Fixpoint update {X : Type} (n : nat) (x: X)
               (l : list (nat * X)) { struct l }: list (nat * X) :=
  match l with
    | [] => []
    (* for now, ignore binding value n' !!! *)
    | (n',a) :: l'  => if beq_nat n (length l') then (n',x)::l' else (n',a) :: update n x l'
  end.



(* LOCALLY NAMELESS *)

Inductive closed_rec: nat -> ty -> Prop :=
| cl_nof: forall k,
    closed_rec k TNoF
| cl_top: forall k,
    closed_rec k TTop
| cl_bot: forall k,
    closed_rec k TBot
| cl_bool: forall k,
    closed_rec k TBool
| cl_fun: forall k m T1 T2,
    closed_rec k T1 ->
    closed_rec k T2 ->
    closed_rec k (TFun m T1 T2)
| cl_mem: forall k T1 T2,
    closed_rec k T1 ->
    closed_rec k T2 ->
    closed_rec k (TMem T1 T2)
| cl_and: forall k T1 T2,
    closed_rec k T1 ->
    closed_rec k T2 ->
    closed_rec k (TAnd T1 T2)
| cl_bind: forall k T1,
    closed_rec (S k) T1 ->
    closed_rec k (TBind T1)
| cl_sel: forall k x,
    closed_rec k (TSel x)
| cl_selb: forall k i,
    k > i ->
    closed_rec k (TSelB i)
.

Hint Constructors closed_rec.

Definition closed j T := closed_rec j T.


Fixpoint open_rec (k: nat) (u: id) (T: ty) { struct T }: ty :=
  match T with
    | TSel x      => TSel x (* free var remains free. functional, so we can't check for conflict *)
    | TSelB i     => if beq_nat k i then TSel u else TSelB i
    | TBind T1    => TBind (open_rec (S k) u T1)
    | TNoF        => TNoF
    | TBot => TBot
    | TTop => TTop
    | TBool       => TBool
    | TAnd T1 T2  => TAnd (open_rec k u T1) (open_rec k u T2)
    | TMem T1 T2  => TMem (open_rec k u T1) (open_rec k u T2)
    | TFun m T1 T2  => TFun m (open_rec k u T1) (open_rec k u T2)
  end.

Definition open u T := open_rec 0 u T.

(* sanity check *)
Example open_ex1: open 9 (TBind (TAnd (TMem TBot TTop) (TFun 0 (TSelB 1) (TSelB 0)))) =
                      (TBind (TAnd (TMem TBot TTop) (TFun 0 (TSel  9) (TSelB 0)))).
Proof. compute. eauto. Qed.


Lemma closed_no_open: forall T x j,
  closed_rec j T ->
  T = open_rec j x T.
Proof.
  intros. induction H; intros; eauto;
  try solve [compute; compute in IHclosed_rec; rewrite <-IHclosed_rec; auto];
  try solve [compute; compute in IHclosed_rec1; compute in IHclosed_rec2; rewrite <-IHclosed_rec1; rewrite <-IHclosed_rec2; auto].

  Case "TSelB".
    unfold open_rec. assert (k <> i). omega. 
    apply beq_nat_false_iff in H0.
    rewrite H0. auto.
Qed.

Lemma closed_upgrade: forall i j T,
 closed_rec i T ->
 j >= i ->
 closed_rec j T.
Proof.
 intros. generalize dependent j. induction H; intros; eauto.
 Case "TBind". econstructor. eapply IHclosed_rec. omega.
 Case "TSelB". econstructor. omega.
Qed.


Hint Unfold open.
Hint Unfold closed.


(* ############################################################ *)
(* Static properties: type assignment, subtyping, ... *)
(* ############################################################ *)

(* TODO: wf is not up to date *)

(* static type expansion.
   needs to imply dynamic subtyping / value typing. *)
Inductive tresolve: id -> ty -> ty -> Prop :=
  | tr_self: forall x T,
             tresolve x T T
  | tr_and1: forall x T1 T2 T,
             tresolve x T1 T ->
             tresolve x (TAnd T1 T2) T
  | tr_and2: forall x T1 T2 T,
             tresolve x T2 T ->
             tresolve x (TAnd T1 T2) T
  | tr_unpack: forall x T2 T3 T,
             open x T2 = T3 ->
             tresolve x T3 T ->
             tresolve x (TBind T2) T
.

Tactic Notation "tresolve_cases" tactic(first) ident(c) :=
  first;
  [ Case_aux c "Self" |
    Case_aux c "And1" |
    Case_aux c "And2" |
    Case_aux c "Bind" ].


(* static type well-formedness.
   needs to imply dynamic subtyping. *)
Inductive wf_type : tenv -> ty -> Prop :=
| wf_top: forall env,
    wf_type env TNoF
| wf_bool: forall env,
    wf_type env TBool
| wf_and: forall env T1 T2,
             wf_type env T1 ->
             wf_type env T2 ->
             wf_type env (TAnd T1 T2)
| wf_mem: forall env TL TU,
             wf_type env TL ->
             wf_type env TU ->
             wf_type env (TMem TL TU)
| wf_fun: forall env f T1 T2,
             wf_type env T1 ->
             wf_type env T2 ->
             wf_type env (TFun f T1 T2)
                     
| wf_sel: forall envz x TE TL TU,
            index x envz = Some (TE) ->
            tresolve x TE (TMem TL TU) ->
            wf_type envz (TSel x)

| wf_selb: forall envz x, (* note: disregarding bind-scope *)
             wf_type envz (TSelB x)
| wf_bind: forall envz T,
             wf_type envz T ->
             wf_type envz (TBind T)

.

Tactic Notation "wf_cases" tactic(first) ident(c) :=
  first;
  [ Case_aux c "Top" |
    Case_aux c "Bool" |
    Case_aux c "And" |
    Case_aux c "MemA" |
    Case_aux c "Mem" |
    Case_aux c "Fun" |
    Case_aux c "Sel" |
    Case_aux x "SelB" |
    Case_aux c "Bind" ].



(* this is the version we can narrow *)

Inductive stp : bool -> tenv -> ty -> ty -> nat -> Prop := 

| stp_bot: forall G1 T n1,
    stp true G1 TBot T n1

| stp_top: forall G1 T n1,
    stp true G1 T TTop n1
             
| stp_bool: forall G1 n1,
    stp true G1 TBool TBool n1

| stp_fun: forall m G1 T11 T12 T21 T22 n1 n2,
    stp false G1 T21 T11 n1 ->
    stp true G1 T12 T22 n2 ->
    stp true G1 (TFun m T11 T12) (TFun m T21 T22) (S (n1+n2))

| stp_mem: forall G1 T11 T12 T21 T22 n1 n2 n3,
    stp false G1 T21 T11 n1 ->
    stp true G1 T11 T12 n2 -> (* NOT SO EASY TO ADD: build_mem! *)
    stp true G1 T12 T22 n3 ->
    stp true G1 (TMem T11 T12) (TMem T21 T22) (S (n1+n2+n3))
        
| stp_sel2: forall x T1 TX G1 n1,
    index x G1 = Some TX ->
    stp false G1 TX (TMem T1 TTop) n1 ->
    stp true G1 T1 (TSel x) (S n1)
| stp_sel1: forall x T2 TX G1 n1,
    index x G1 = Some TX ->
    stp false G1 TX (TMem TBot T2) n1 ->
    stp true G1 (TSel x) T2 (S n1)
| stp_selx: forall x G1 n1,
    stp true G1 (TSel x) (TSel x) (S n1)
                  
(* TODO!
| stp_bind2: forall f G1 T1 T2 TA2 n1,
    stp true ((f,T1)::G1) T1 T2 n1 ->
    open (length G1) TA2 = T2 ->                
    stp true G1 T1 (TBind TA2) (S n1)
| stp_bind1: forall f G1 T1 T2 TA1 n1,
    stp true ((f,T1)::G1) T1 T2 n1 ->
    open (length G1) TA1 = T1 ->                
    stp true G1 (TBind TA1) T2 (S n1)
... or at least...
*)
| stp_bindx: forall G1 T1 T2 TA1 TA2 n1,
    stp false ((length G1,T1)::G1) T1 T2 n1 ->
    open (length G1) TA1 = T1 ->                
    open (length G1) TA2 = T2 ->
    stp true G1 (TBind TA1) (TBind TA2) (S n1)

| stp_transf: forall G1 T1 T2 T3 n1 n2,
    stp true G1 T1 T2 n1 ->
    stp false G1 T2 T3 n2 ->           
    stp false G1 T1 T3 (S (n1+n2))

| stp_wrapf: forall G1 T1 T2 n1,
    stp true G1 T1 T2 n1 ->
    stp false G1 T1 T2 (S n1)       
.


(* implementable types *)
Inductive itp: tenv -> ty -> nat -> Prop :=

| itp_top: forall G1 n1,
    itp G1 TTop n1
| itp_bool: forall G1 n1,
    itp G1 TBool n1
(* TODO: we should have another mem case,
   if lower bound is bot, upper bound need
   not be realizable (?) *)
| itp_mem: forall G1 TL TU n1 n2,
(*    stp true G1 TL TU n1 -> (* may or may not be needed *) *)
    itp G1 TU n2 -> 
    itp G1 (TMem TL TU) (S (n1+n2))
| itp_bind: forall G1 T1 TA1 n1,
    itp ((length G1,T1)::G1) T1 n1 ->  (* TAKING THE OTHER ONE *)
    open (length G1) TA1 = T1 ->
    itp G1 (TBind TA1) (S n1)
| itp_sel: forall G1 TX x n1,
    index x G1 = Some TX ->
    itp G1 TX n1 -> (* could / should we rely on env_itp to provide this? *)
    itp G1 (TSel x) (S n1)
.




(* this is the version we can trans *)

Inductive stp2 : bool -> tenv -> ty -> ty -> nat -> Prop := 

| stp2_bot: forall G1 T n1,
    stp2 true G1 TBot T n1

| stp2_top: forall G1 T n1,
    stp2 true G1 T TTop n1
             
| stp2_bool: forall G1 n1,
    stp2 true G1 TBool TBool n1

| stp2_fun: forall m G1 T11 T12 T21 T22 n1 n2,
    stp2 false G1 T21 T11 n1 ->
    stp2 true G1 T12 T22 n2 ->
    stp2 true G1 (TFun m T11 T12) (TFun m T21 T22) (S (n1+n2))

| stp2_mem: forall G1 T11 T12 T21 T22 n1 n2 n3,
    stp2 false G1 T21 T11 n1 ->
    stp2 true G1 T11 T12 n2 -> (* NOT SO EASY TO ADD: build_mem! *)
    stp2 true G1 T12 T22 n3 ->
    stp2 true G1 (TMem T11 T12) (TMem T21 T22) (S (n1+n2+n3))
        
| stp2_sel2: forall x T1 TX G1 n1 n2,
    index x G1 = Some TX ->
    itp G1 TX n2 -> 
    stp2 true G1 TX (TMem T1 TTop) n1 ->
    stp2 true G1 T1 (TSel x) (S (n1+n2))
| stp2_sel1: forall x T2 TX G1 n1 n2,
    index x G1 = Some TX ->
    itp G1 TX n2 ->
    stp2 true G1 TX (TMem TBot T2) n1 ->
    stp2 true G1 (TSel x) T2 (S (n1+n2))
| stp2_selx: forall x G1 n1,
    stp2 true G1 (TSel x) (TSel x) (S n1)
                  
(* TODO!
| stp_bind2: forall f G1 T1 T2 TA2 n1,
    stp true ((f,T1)::G1) T1 T2 n1 ->
    open (length G1) TA2 = T2 ->                
    stp true G1 T1 (TBind TA2) (S n1)
| stp_bind1: forall f G1 T1 T2 TA1 n1,
    stp true ((f,T1)::G1) T1 T2 n1 ->
    open (length G1) TA1 = T1 ->                
    stp true G1 (TBind TA1) T2 (S n1)
... or at least...
*)
| stp2_bindx: forall G1 T1 T2 TA1 TA2 n1,
    stp false ((length G1,T1)::G1) T1 T2 n1 ->  (* TAKING THE OTHER ONE *)
    open (length G1) TA1 = T1 ->                
    open (length G1) TA2 = T2 ->
    (* no itp here, needs to come from env_itp if extracting things *)
    (* itp ((length G1,T1)::G1) T1 n2 -> *)
    stp2 true G1 (TBind TA1) (TBind TA2) (S n1)

| stp2_transf: forall G1 T1 T2 T3 n1 n2,
    stp2 true G1 T1 T2 n1 ->
    stp2 false G1 T2 T3 n2 ->           
    stp2 false G1 T1 T3 (S (n1+n2))

| stp2_wrapf: forall G1 T1 T2 n1,
    stp2 true G1 T1 T2 n1 ->
    stp2 false G1 T1 T2 (S n1)       
.


Definition itp2 a b c := itp a b c.


(* this is the version that has invertible bindx *)

Inductive stp3 : bool -> tenv -> ty -> ty -> nat -> Prop := 

| stp3_bot: forall G1 T n1,
    stp3 true G1 TBot T n1

| stp3_top: forall G1 T n1,
    stp3 true G1 T TTop n1
             
| stp3_bool: forall G1 n1,
    stp3 true G1 TBool TBool n1

| stp3_fun: forall m G1 T11 T12 T21 T22 n1 n2,
    stp2 false G1 T21 T11 n1 ->
    stp2 true G1 T12 T22 n2 ->
    stp3 true G1 (TFun m T11 T12) (TFun m T21 T22) (S (n1+n2))

| stp3_mem: forall G1 T11 T12 T21 T22 n1 n2,
    stp2 false G1 T21 T11 n1 ->
    stp3 true G1 T12 T22 n2 ->
    stp3 true G1 (TMem T11 T12) (TMem T21 T22) (S (n1+n2))
        
| stp3_sel2: forall x T1 TX G1 n1 n2,
    index x G1 = Some TX ->
    itp G1 TX n2 -> 
    stp3 true G1 TX (TMem T1 TTop) n1 ->
    stp3 true G1 T1 (TSel x) (S (n1+n2))
| stp3_sel1: forall x T2 TX G1 n1 n2,
    index x G1 = Some TX ->
    itp G1 TX n2 ->
    stp3 true G1 TX (TMem TBot T2) n1 ->
    stp3 true G1 (TSel x) T2 (S (n1+n2))
| stp3_selx: forall x G1 n1,
    stp3 true G1 (TSel x) (TSel x) (S n1)
                  
| stp3_bindx: forall G1 T1 T2 TA1 TA2 n1 n2,
    stp3 true ((length G1,T1)::G1) T1 T2 n1 -> (* CAN INVERT *)
    open (length G1) TA1 = T1 ->                
    open (length G1) TA2 = T2 ->
    itp ((length G1,T1)::G1) T1 n2 -> 
    stp3 true G1 (TBind TA1) (TBind TA2) (S (n1+n2))

| stp3_transf: forall G1 T1 T2 T3 n1 n2,
    stp3 true G1 T1 T2 n1 ->
    stp3 false G1 T2 T3 n2 ->           
    stp3 false G1 T1 T3 (S (n1+n2))

| stp3_wrapf: forall G1 T1 T2 n1,
    stp3 true G1 T1 T2 n1 ->
    stp3 false G1 T1 T2 (S n1)       
.


Definition itp3 a b c := itp a b c.




(*
XXXX ---- XXXX

intersection case for narrowing:

(1) bad bounds

x:Bot..Top, y:Hi..Hi
x.A /\ y.B,     

narrow x to Lo..Lo

now x.A /\ y.B has bad bounds Hi..Lo

but this object can't exist, it cannot be in context, so all is good !!!

however, the original type can be in context, and this is the trouble case.
(because we need to show it remains implementable in narrowing).

similarly, the original type can be the body of a self type.

x={A:Bot..{B:Bot..Top}}
{z => x.A & {B:Hi..Hi }}

narrow x to {A:Bot..{B:Lo..Lo}} 

the context is still implementable,
but z's body is no longer implementable.

but how can the narrowing happen? x must be bound by a self type...

maybe this will constrain things?



(2) expansion can be lost already, without looking at bounds

*)






(*

what about intersection types:

STP

  T <: T1,  T <: T2
  -----------------
  T <: T1 /\ T2


  T1 <: T,  T2 wfe
  ----------------
  T1 /\ T2 <: T


  T1 wfe,  T2 <: T 
  ----------------
  T1 /\ T2 <: T


EXP

  T1 <x {A: L1..U1},  T2 <x {A: L2..U2}
  ------------------------------------
  T1 /\ T2 <x {A: L1 \/ L2 .. U1 /\ U2 }


  T1 <x {A: L1..U1},  A not in dom(T2)
  ------------------------------------
  T1 /\ T2 <x {A: L1..U1}


  A not in dom(T1),  T2 <x {A: L2..U2}
  ------------------------------------
  T1 /\ T2 <x {A: L2..U2}


Problem case (bad bounds):

  (Int..Int) /\ (String..String)

Expansion:

  (Int \/ String) .. (Int /\ String) <--- not <:


CONSTRAINTS:
  - need good bounds (L < U) for stpd_trans_cross
  - not part of regular stp. needs to come from env
  - but need to be able to do induction on it

HYPOTHESIS:
  - put itp in stp_sel1,sel2 evidence: this mirrors 
    env_itp, but enables induction
  - narrow uses env_itp to get new itp (output size 
    doesn't matter)



Need itp_exp (example):

  itp (L1..U1) /\ (L2..U2)
  (L1..U1) /\ (L2..U2) <: L..U  [n+1]
--->
  (L1..U1) /\ (L2..U2)  <x  (L1 \/ L2 .. U1 /\ U2)
  (L1 \/ L2  <:  U1 /\ U2)   [n]
  
  (L1 \/ L2 .. U1 /\ U2)  <:  L..U
  itp U1 /\ U2
*)








Tactic Notation "stp_cases" tactic(first) ident(c) :=
  first;
  [ 
    Case_aux c "Bot < ?" |
    Case_aux c "? < Top" |
    Case_aux c "Bool < Bool" |
    Case_aux c "Fun < Fun" |
    Case_aux c "Mem < Mem" |
    Case_aux c "? < Sel" |
    Case_aux c "Sel < ?" |
    Case_aux c "Sel < Sel" |
    Case_aux c "Bind < Bind" |
    Case_aux c "Trans" |
    Case_aux c "Wrap"
  ].


Hint Resolve ex_intro.

Hint Constructors stp.
Hint Constructors itp.
Hint Constructors stp2.
Hint Constructors stp3.


(* ############################################################ *)
(* Examples *)
(* ############################################################ *)


(*
THIS IS NOW FALSE: lhs must expand.

Example ex1: exists n, stp true nil (TBind TBot) (TBind TTop) n.
Proof.
 eexists. eapply stp_bindx. eapply stp_bot. eauto. (* false - bot doesn't exp! *).
Grab Existential Variables. apply 0.
Qed.
 *)

Example ex2: exists n, stp true nil
   (TBind (TMem TBool TBool))
   (TBind (TMem TBot TTop)) n.
Proof.
  eexists. eapply stp_bindx. eapply stp_wrapf. eapply stp_mem.  eapply stp_wrapf. eapply stp_bot.
  eapply stp_bool.
  eapply stp_top. compute. eauto. compute. eauto. 
Grab Existential Variables. apply 0. apply 0. apply 0. 
Qed.

Example ex3: exists n, stp true nil
   (TBind (TMem TBool TBool))
   (TBind (TMem (TSelB 0) (TSelB 0))) n. (* can't do much with this *)
Proof.
  eexists. eapply stp_bindx.
  instantiate (3 := (TMem TBool TBool)).
  instantiate (2 := (TMem (TSel 0) (TSel 0))).

  eapply stp_wrapf.
  eapply stp_mem. eapply stp_wrapf.
  eapply stp_sel1. compute. eauto. eapply stp_wrapf. eapply stp_mem. eauto. eauto. eauto. eauto.
  eapply stp_sel2. compute. eauto. eauto.
  eauto. eauto. 
Grab Existential Variables. apply 0. apply 0. apply 0. apply 0. apply 0. apply 0. apply 0. 
Qed.



(* ############################################################ *)
(* Proofs *)
(* ############################################################ *)



Definition stpd b G1 T1 T2 := exists n, stp b G1 T1 T2 n.
Definition itpd G1 T1 := exists n, itp G1 T1 n.

Definition stpd2 b G1 T1 T2 := exists n, stp2 b G1 T1 T2 n.
Definition itpd2 G1 T1 := exists n, itp2 G1 T1 n.

Definition stpd3 b G1 T1 T2 := exists n, stp3 b G1 T1 T2 n.
Definition itpd3 G1 T1 := exists n, itp3 G1 T1 n.


Hint Unfold stpd.
Hint Unfold itpd.

Hint Unfold stpd2.
Hint Unfold itpd2.

Hint Unfold stpd3.
Hint Unfold itpd3.

Ltac ep := match goal with
             | [ |- stp ?M ?G1 ?T1 ?T2 ?N ] => assert (exists (x:nat), stp M G1 T1 T2 x) as EEX
           end.

Ltac eu := match goal with
             | H: stpd _ _ _ _ |- _ => destruct H
             | H: itpd _ _ |- _ => destruct H
             | H: stpd2 _ _ _ _ |- _ => destruct H
             | H: itpd2 _ _ |- _ => destruct H
             | H: stpd3 _ _ _ _ |- _ => destruct H
             | H: itpd3 _ _ |- _ => destruct H
(*             | H: exists n: nat ,  _ |- _  =>
               destruct H as [e P] *)
           end.

Lemma stpd_bot: forall G1 T,
    stpd true G1 TBot T.
Proof. intros. exists 0. eauto. Qed.
Lemma stpd_top: forall G1 T,
    stpd true G1 T TTop.
Proof. intros. exists 0. eauto. Qed.
Lemma stpd_bool: forall G1,
    stpd true G1 TBool TBool.
Proof. intros. exists 0. eauto. Qed.
Lemma stpd_fun: forall m G1 T11 T12 T21 T22,
    stpd false G1 T21 T11 ->
    stpd true G1 T12 T22 ->
    stpd true G1 (TFun m T11 T12) (TFun m T21 T22).
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd_mem: forall G1 T11 T12 T21 T22,
    stpd false G1 T21 T11 ->
    stpd true G1 T11 T12 ->
    stpd true G1 T12 T22 ->
    stpd true G1 (TMem T11 T12) (TMem T21 T22).
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd_sel2: forall x T1 TX G1,
    index x G1 = Some TX ->
    stpd false G1 TX (TMem T1 TTop) ->
    stpd true G1 T1 (TSel x).
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd_sel1:  forall x T2 TX G1,
    index x G1 = Some TX ->
    stpd false G1 TX (TMem TBot T2) ->
    stpd true G1 (TSel x) T2.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd_selx: forall x G1,
    stpd true G1 (TSel x) (TSel x).
Proof. intros. repeat eu. exists 1. eauto. Qed.
Lemma stpd_bindx: forall G1 T1 T2 TA1 TA2,
    stpd false ((length G1,T1)::G1) T1 T2 ->
    open (length G1) TA1 = T1 ->                
    open (length G1) TA2 = T2 ->
    (* exp G1 T1 (TMem TL TU) -> *)
    (* stpd true G1 TL TU -> *)
    stpd true G1 (TBind TA1) (TBind TA2).
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd_transf: forall G1 T1 T2 T3,
    stpd true G1 T1 T2 ->
    stpd false G1 T2 T3 ->           
    stpd false G1 T1 T3.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd_wrapf: forall G1 T1 T2,
    stpd true G1 T1 T2 ->
    stpd false G1 T1 T2. 
Proof. intros. repeat eu. eauto. Qed.

Lemma stpd2_bot: forall G1 T,
    stpd2 true G1 TBot T.
Proof. intros. exists 0. eauto. Qed.
Lemma stpd2_top: forall G1 T,
    stpd2 true G1 T TTop.
Proof. intros. exists 0. eauto. Qed.
Lemma stpd2_bool: forall G1,
    stpd2 true G1 TBool TBool.
Proof. intros. exists 0. eauto. Qed.
Lemma stpd2_fun: forall m G1 T11 T12 T21 T22,
    stpd2 false G1 T21 T11 ->
    stpd2 true G1 T12 T22 ->
    stpd2 true G1 (TFun m T11 T12) (TFun m T21 T22).
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd2_mem: forall G1 T11 T12 T21 T22,
    stpd2 false G1 T21 T11 ->
    stpd2 true G1 T11 T12 ->
    stpd2 true G1 T12 T22 ->
    stpd2 true G1 (TMem T11 T12) (TMem T21 T22).
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd2_sel2: forall x T1 TX G1,
    index x G1 = Some TX ->
    itpd2 G1 TX ->
    stpd2 true G1 TX (TMem T1 TTop) ->
    stpd2 true G1 T1 (TSel x).
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd2_sel1:  forall x T2 TX G1,
    index x G1 = Some TX ->
    itpd2 G1 TX ->
    stpd2 true G1 TX (TMem TBot T2) ->
    stpd2 true G1 (TSel x) T2.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd2_selx: forall x G1,
    stpd2 true G1 (TSel x) (TSel x).
Proof. intros. repeat eu. exists 1. eauto. Qed.
Lemma stpd2_bindx: forall G1 T1 T2 TA1 TA2,
    stpd false ((length G1,T1)::G1) T1 T2 -> (* !!! *)
    open (length G1) TA1 = T1 ->                
    open (length G1) TA2 = T2 ->
    (* exp G1 T1 (TMem TL TU) -> *)
    (* stpd true G1 TL TU -> *)
    (* itpd2 ((length G1,T1)::G1) T1 -> *)
    stpd2 true G1 (TBind TA1) (TBind TA2).
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd2_transf: forall G1 T1 T2 T3,
    stpd2 true G1 T1 T2 ->
    stpd2 false G1 T2 T3 ->           
    stpd2 false G1 T1 T3.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd2_wrapf: forall G1 T1 T2,
    stpd2 true G1 T1 T2 ->
    stpd2 false G1 T1 T2. 
Proof. intros. repeat eu. eauto. Qed.


Lemma stpd3_bot: forall G1 T,
    stpd3 true G1 TBot T.
Proof. intros. exists 0. eauto. Qed.
Lemma stpd3_top: forall G1 T,
    stpd3 true G1 T TTop.
Proof. intros. exists 0. eauto. Qed.
Lemma stpd3_bool: forall G1,
    stpd3 true G1 TBool TBool.
Proof. intros. exists 0. eauto. Qed.
Lemma stpd3_fun: forall m G1 T11 T12 T21 T22,
    stpd2 false G1 T21 T11 ->
    stpd2 true G1 T12 T22 ->
    stpd3 true G1 (TFun m T11 T12) (TFun m T21 T22).
Proof. intros. repeat eu. info_eauto. Qed.
Lemma stpd3_mem: forall G1 T11 T12 T21 T22,
    stpd2 false G1 T21 T11 ->
    stpd3 true G1 T12 T22 ->
    stpd3 true G1 (TMem T11 T12) (TMem T21 T22).
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd3_sel2: forall x T1 TX G1,
    index x G1 = Some TX ->
    itpd3 G1 TX ->
    stpd3 true G1 TX (TMem T1 TTop) ->
    stpd3 true G1 T1 (TSel x).
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd3_sel1:  forall x T2 TX G1,
    index x G1 = Some TX ->
    itpd3 G1 TX ->
    stpd3 true G1 TX (TMem TBot T2) ->
    stpd3 true G1 (TSel x) T2.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd3_selx: forall x G1,
    stpd3 true G1 (TSel x) (TSel x).
Proof. intros. repeat eu. exists 1. eauto. Qed.
Lemma stpd3_bindx: forall G1 T1 T2 TA1 TA2,
    stpd3 true ((length G1,T1)::G1) T1 T2 -> (* !!! *)
    open (length G1) TA1 = T1 ->                
    open (length G1) TA2 = T2 ->
    (* exp G1 T1 (TMem TL TU) -> *)
    (* stpd true G1 TL TU -> *)
    itpd3 ((length G1,T1)::G1) T1 -> 
    stpd3 true G1 (TBind TA1) (TBind TA2).
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd3_transf: forall G1 T1 T2 T3,
    stpd3 true G1 T1 T2 ->
    stpd3 false G1 T2 T3 ->           
    stpd3 false G1 T1 T3.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd3_wrapf: forall G1 T1 T2,
    stpd3 true G1 T1 T2 ->
    stpd3 false G1 T1 T2. 
Proof. intros. repeat eu. eauto. Qed.







Ltac index_subst := match goal with
                 | H1: index ?x ?G = ?V1 , H2: index ?x ?G = ?V2 |- _ => rewrite H1 in H2; inversion H2; subst
                 | _ => idtac
               end.

Lemma stp0f_trans: forall n n1 G1 T1 T2 T3,
    stp false G1 T1 T2 n1 ->
    stpd false G1 T2 T3 ->
    n1 <= n ->
    stpd false G1 T1 T3.
Proof.
  intros n. induction n.
  - Case "z".
    intros. assert (n1 = 0). omega. subst. inversion H.
  - Case "S n".
    intros. inversion H.
    + eapply stpd_transf. eexists. eapply H2. eapply IHn. eapply H3. eapply H0. omega.
    + destruct H0. eapply stpd_transf. eexists. eapply H2. eexists. eapply H0.
Qed.  

Lemma stp0f2_trans: forall n n1 G1 T1 T2 T3,
    stp2 false G1 T1 T2 n1 ->
    stpd2 false G1 T2 T3 ->
    n1 <= n ->
    stpd2 false G1 T1 T3.
Proof.
  intros n. induction n.
  - Case "z".
    intros. assert (n1 = 0). omega. subst. inversion H.
  - Case "S n".
    intros. inversion H.
    + eapply stpd2_transf. eexists. eapply H2. eapply IHn. eapply H3. eapply H0. omega.
    + destruct H0. eapply stpd2_transf. eexists. eapply H2. eexists. eapply H0.
Qed.  



(* implementable context *)
Definition env_itp G := forall x T, index x G = Some T -> itpd G T.


(* left:  may use axiom but has size. must shrink *)
(* right: no axiom but can grow *)

Definition trans_on n2 :=
  forall m G1 T1 T2 T3,
      stp2 m G1 T1 T2 n2 ->
      stpd2 true G1 T2 T3 ->
      stpd2 true G1 T1 T3.

Hint Unfold trans_on.


Definition trans_up n := forall n1, n1 <= n ->
                      trans_on n1.
Hint Unfold trans_up.

Lemma trans_le: forall n n1,
                      trans_up n ->
                      n1 <= n ->
                      trans_on n1
.
Proof. intros. unfold trans_up in H. eapply H. eauto. Qed.

Lemma upd_length_same: forall {X} G x (T:X),
              length G = length (update x T G).
Proof.
  intros X G x T. induction G.
  - simpl. reflexivity.
  - destruct a as [n' Ta]. simpl.
    remember (beq_nat x (length G)).
    destruct b.
    + simpl. reflexivity.
    + simpl. f_equal. apply IHG.
Qed.

Lemma upd_hit: forall {X} G G' x x' (T:X) T',
              index x G = Some T ->
              update x' T' G = G' ->
              beq_nat x x' = true ->
              index x G' = Some T'.
Proof.
  intros X G G' x x' T T' Hi Hu Heq.
  subst. induction G.
  - simpl in Hi. inversion Hi.
  - destruct a as [n' Ta]. simpl in Hi.
    remember (beq_nat x (length G)).
    apply beq_nat_true in Heq.
    destruct b.
    + simpl.
      apply beq_nat_eq in Heqb.
      subst. subst.
      rewrite <- beq_nat_refl.
      simpl.
      rewrite <- beq_nat_refl.
      reflexivity.
    + simpl.
      subst.
      rewrite <- Heqb.
      simpl.
      assert ((length G) = (length (update x' T' G))) as HnG. {
        apply upd_length_same.
      }
      rewrite <- HnG.
      rewrite <- Heqb.
      apply IHG.
      apply Hi.
Qed.

Lemma upd_miss: forall {X} G G' x x' (T:X) T',
              index x G = Some T ->
              update x' T' G = G' ->
              beq_nat x x' = false ->
              index x G' = Some T.
Proof.
  intros X G G' x x' T T' Hi Hu Heq.
  subst. induction G.
  - simpl in Hi. inversion Hi.
  - destruct a as [n' Ta]. simpl in Hi. simpl.
    remember (beq_nat x (length G)).
    destruct b.
    + apply beq_nat_eq in Heqb.
      subst.
      rewrite beq_nat_sym. rewrite Heq.
      simpl.
      assert ((length G) = (length (update x' T' G))) as HnG. {
        apply upd_length_same.
      }
      rewrite <- HnG.
      rewrite <- beq_nat_refl.
      apply Hi.
    + remember (beq_nat x' (length G)) as b'.
      destruct b'.
      * simpl.
        rewrite <- Heqb.
        apply Hi.
      * simpl.
        assert ((length G) = (length (update x' T' G))) as HnG. {
          apply upd_length_same.
        }
        rewrite <- HnG.
        rewrite <- Heqb.
        apply IHG.
        apply Hi.
Qed.


Lemma index_max : forall X vs n (T: X),
                       index n vs = Some T ->
                       n < length vs.
Proof.
  intros X vs. induction vs.
  Case "nil". intros. inversion H.
  Case "cons".
  intros. inversion H. destruct a.
  case_eq (beq_nat n (length vs)); intros E.
  SCase "hit".
  rewrite E in H1. inversion H1. subst.
  eapply beq_nat_true in E. 
  unfold length. unfold length in E. rewrite E. eauto.
  SCase "miss".
  rewrite E in H1.
  assert (n < length vs). eapply IHvs. apply H1.
  compute. eauto.
Qed.

  
Lemma index_extend : forall X vs n a (T: X),
                       index n vs = Some T ->
                       index n (a::vs) = Some T.

Proof.
  intros.
  assert (n < length vs). eapply index_max. eauto.
  assert (n <> length vs). omega.
  assert (beq_nat n (length vs) = false) as E. eapply beq_nat_false_iff; eauto.
  unfold index. unfold index in H. rewrite H. rewrite E. destruct a. reflexivity.
Qed.

Lemma update_extend: forall X (T1: X) (TX1: X) G1 G1' x a,
  index x G1 = Some T1 ->
  update x TX1 G1 = G1' ->
  update x TX1 (a::G1) = (a::G1').
Proof.
  intros X T1 TX1 G1 G1' x a Hi Hu.
  assert (x < length G1) as Hlt. {
    eapply index_max.
    eauto.
  }
  assert (x <> length G1) as Hneq by omega.
  assert (beq_nat x (length G1) = false) as E. {
    eapply beq_nat_false_iff; eauto.
  }
  destruct a as [n' Ta].
  simpl. rewrite E. rewrite Hu. reflexivity.
Qed.

Lemma update_pres_len: forall X (TX1: X) G1 G1' x, 
  update x TX1 G1 = G1' ->
  length G1 = length G1'.
Proof.
  intros X TX1 G1 G1' x H. subst. apply upd_length_same.
Qed.

Lemma stp_extend : forall m G1 T1 T2 x v n,
                       stp m G1 T1 T2 n ->
                       stp m ((x,v)::G1) T1 T2 n.
Proof. admit. (*intros. destruct H. eexists. eapply stp_extend1. apply H.*) Qed.


Lemma itp_extend: forall G T n x v,
                         itp G T n ->
                         itp ((x,v)::G) T n.
Proof.
  admit. (* intros. induction H; eauto using index_extend. *)
Qed.


(* currently n,n2 unrelated, but may change. keep in sync with env_itp definition *)
Lemma env_itp_extend : forall G x v,  
                       env_itp G ->
                       itpd ((x,v)::G) v ->  
                       env_itp ((x,v)::G).
Proof.
  intros. unfold env_itp in H. unfold env_itp. intros.
  case_eq (beq_nat x0 (length G)); intros.
  - assert (x0 = (length G)). eapply beq_nat_true_iff; eauto.
    subst x0. unfold index in H1. rewrite H2 in H1. inversion H1. subst v.
    eapply H0.
  - assert (x0 <> (length G)). eapply beq_nat_false_iff; eauto.
    assert (x0 < length ((x,v)::G)). eapply index_max; eauto.
    
    unfold index in H1. rewrite H2 in H1.
    eapply H in H1. destruct H1. eexists. eapply itp_extend. apply H1.
Qed.

Lemma stp_narrow: forall n, forall m G1 T1 T2 n1 n0,
  stp m G1 T1 T2 n0 ->
  n0 <= n ->                    
  forall x TX1 TX2 G1',

    index x G1 = Some TX2 ->
    update x TX1 G1 = G1' ->
    stp false G1' TX1 TX2 n1 ->
    stpd m G1' T1 T2.
Proof.
  intros n.
  induction n.
  (* z *) intros. inversion H0. subst. inversion H; eauto.
  (* s n *)
  intros m G1 T1 T2 n1 n0 H NE.
  inversion H; intros.
  - Case "Bot".
    intros. eapply stpd_bot.
  - Case "Top".
    intros. eapply stpd_top.
  - Case "Bool". 
    intros. eapply stpd_bool.
  - Case "Fun". 
    intros. eapply stpd_fun. eapply IHn; eauto. omega. eapply IHn; eauto. omega.
  - Case "Mem". 
    intros. eapply stpd_mem. eapply IHn; eauto. omega. eapply IHn; eauto. omega. eapply IHn; eauto. omega.
  - Case "Sel2". intros.
    { case_eq (beq_nat x x0); intros E.
      (* hit updated binding *)
      + assert (x = x0) as EX. eapply beq_nat_true_iff; eauto. subst. index_subst. index_subst.
        eapply stpd_sel2. eapply upd_hit; eauto.
        (* trans, and narrow by induction *)
        eapply stp0f_trans. eapply H9. eapply IHn; eauto. omega. eauto.
      (* other binding *)
      + assert (x <> x0) as EX. eapply beq_nat_false_iff; eauto.
        eapply stpd_sel2. eapply upd_miss; eauto.
        (* narrow stp by induction *)
        eapply IHn; eauto. omega.
    }
  - Case "Sel1". intros.
    { case_eq (beq_nat x x0); intros E.
      (* hit updated binding *)
      + assert (x = x0) as EX. eapply beq_nat_true_iff; eauto. subst. index_subst. index_subst. 
        eapply stpd_sel1. eapply upd_hit; eauto.
        (* trans, and narrow by induction *)
        eapply stp0f_trans. eapply H9. eapply IHn; eauto. omega. eauto.
      (* other binding *)
      + assert (x <> x0) as EX. eapply beq_nat_false_iff; eauto.
        eapply stpd_sel1. eapply upd_miss; eauto.
        (* narrow stp by induction *)
        eapply IHn; eauto. omega.
    }
  - Case "Selx". eapply stpd_selx.
  - Case "Bindx".
    assert (length G1 = length G1'). { eapply update_pres_len; eauto. }
    remember (length G1) as L. clear HeqL. subst L.

    eapply stpd_bindx. {
      eapply IHn. eapply H0. omega.
      eapply index_extend; eauto.
      eapply update_extend; eauto.
      eapply stp_extend; eauto.
    }
    eauto.
    eauto.

  - Case "Trans". eapply stpd_transf. eapply IHn; eauto. omega. eapply IHn; eauto. omega.
  - Case "Wrap". eapply stpd_wrapf. eapply IHn; eauto. omega.

    Grab Existential Variables. apply 0. apply 0. apply 0.
Qed.




(* ---------- EXPANSION / MEMBERSHIP ---------- *)
(* In the current version, expansion is an implementation
   detail. We just use it to derive some helper lemmas
   to show that implementable types have good bounds.
*)


(* expansion / membership *)
(* this is the precise version! no slack in lookup *)
(* TODO: need the name for bind? *)
Inductive exp : tenv -> ty -> ty -> Prop :=
(*
| exp_bot: forall G1,
    exp G1 TBot (TMem TTop TBot)  (* causes trouble in inv_mem: need to build stp deriv with smaller n *)
*)
| exp_mem: forall G1 T1 T2,
    exp G1 (TMem T1 T2) (TMem T1 T2)
| exp_sel: forall G1 x T T2 T3 T4 T5,
    index x G1 = Some T ->
    exp G1 T (TMem T2 T3) ->
    exp G1 T3 (TMem T4 T5) ->
    exp G1 (TSel x) (TMem T4 T5) 
.

(*
NOT NEEDED (apparently)
Lemma exp_unique: forall G1 T1 TA1 TA2 TA1L TA2L, 
  exp G1 T1 (TMem TA1L TA1) ->
  exp G1 T1 (TMem TA2L TA2) ->
  TA1 = TA2.
Proof.  Qed.
*)


(* key lemma that relates exp and stp. result has bounded size. *)
Lemma stpd_inv_mem: forall n n1 G1, 

  forall TA1 TA2 TA1L TA2L T1,
  exp G1 T1 (TMem TA1L TA1) ->
  stp2 true G1 T1 (TMem TA2L TA2) n1 ->
  n1 <= n ->
  exists n3, stp2 true G1 (TMem TA1L TA1) (TMem TA2L TA2) n3 /\ n3 <= n1. (* should be semantic eq! *)
Proof.
  intros n1. induction n1.
  (*z*) intros. inversion H0; subst; inversion H1; subst; try omega. try inversion H.
  (* s n *)
  intros. inversion H.
(*  - Case "bot". subst. exists 0. split. eapply stp_mem. eauto. eauto. inversion H0.  subst. omega. *)
  - Case "mem". subst. exists n0. auto. (*inversion H0. subst. exists n3. split. eauto. omega. *)
  - Case "sel".
    subst.
    inversion H0.
    repeat index_subst. clear H4.
    
    assert (exists n0 : nat, stp2 true G1 (TMem T2 T3) (TMem TBot (TMem TA2L TA2)) n0 /\ n0 <= n2) as S1.
    eapply (IHn1 n2). apply H7. apply H6. omega.

    destruct S1 as [? [S1 ?]]. inversion S1. subst.

    assert (exists n0 : nat, stp2 true G1 (TMem TA1L TA1) (TMem TA2L TA2) n0 /\ n0 <= n5) as S2.
    eapply (IHn1 n5). apply H8. apply H16. omega.

    destruct S2 as [? [S2 ?]].
    
    eexists. split. apply S2. omega.
Qed.


Definition env_good_bounds G1 :=
  forall TX T2 T3 x,
    index x G1 = Some TX ->
    exp G1 TX (TMem T2 T3) ->
    exists n2, stp2 true G1 T2 T3 n2.

(*
could go this route, if itp contains L<U evidence,
but currently not needed.

Lemma env_itp_gb: forall G1 n1,
  env_itp G1 n1 ->
  env_good_bounds G1.                  
Proof. Qed.
*)


(* dual case *)
Lemma stpd_build_mem: forall n1 G1, 
  forall TA1 TA2 TA1L TA2L T1,
    exp G1 T1 (TMem TA1L TA1) ->
    env_good_bounds G1 ->
    env_itp G1 -> (* to obtain itp evidence for sel1 result *)
  stp2 true G1 (TMem TA1L TA1) (TMem TA2L TA2) n1 ->
  exists n3, stp2 true G1 T1 (TMem TA2L TA2) n3.
Proof.
  (* now taking 'good bounds' evidence as input *)

  intros.
  generalize dependent n1.
  generalize dependent TA2.
  generalize dependent TA2L.
  induction H.
  - Case "mem".
    subst. eexists. eauto.
  - Case "sel".
    intros. subst.
    (* inversion H2. subst. index_subst. subst. *)
    assert (exists n3, stp2 true G1 T3 (TMem TA2L TA2) n3) as IX2. {
      eapply IHexp2. eauto. eauto. eauto.
    }
    destruct IX2 as [n4 IX2].
    (* here we need T2 < T3 to construct stp_mem *)
    (* current stragety is to get it from env_good_bounds *)
    assert (exists n2, stp2 true G1 T2 T3 n2) as IY. eauto.
    destruct IY as [? IY].
    assert (exists n3, stp2 true G1 T (TMem TBot (TMem TA2L TA2)) n3) as IX. {
      eapply IHexp1. eauto. eauto. eapply stp2_mem. eapply stp2_wrapf. eapply stp2_bot.
      apply IY. apply IX2. 
    }
    destruct IX.
    assert (itpd2 G1 T) as IZ. { eapply H1; eauto. (* from env_itp *) }
    destruct IZ.                          
    subst. eexists. eapply stp2_sel1. eauto. eauto. eauto.
    Grab Existential Variables. apply 0.
Qed.



(* trans helpers -- these are based on exp only and currently not used *)

Lemma stpde_trans_lo: forall G1 T1 T2 TX TXL TXU,
  stpd2 true G1 T1 T2 ->                     
  stpd2 true G1 TX (TMem T2 TTop) ->
  exp G1 TX (TMem TXL TXU) ->
  env_itp G1 ->
  env_good_bounds G1 ->
  stpd2 true G1 TX (TMem T1 TTop).
Proof.
  intros. repeat eu.
  assert (exists nx, stp2 true G1 (TMem TXL TXU) (TMem T2 TTop) nx /\ nx <= x) as E. eapply (stpd_inv_mem x). eauto. eauto. omega.
  destruct E as [nx [ST X]].
  inversion ST. subst.

  eapply stpd_build_mem. eauto. eauto. eauto. eapply stp2_mem. eapply stp2_transf. eauto. eauto. eauto. eauto.
Qed.

Lemma stpde_trans_hi: forall G1 T1 T2 TX n1 TXL TXU,
  stpd2 true G1 T1 T2 ->                     
  stp2 true G1 TX (TMem TBot T1) n1 ->
  exp G1 TX (TMem TXL TXU) ->
  env_itp G1 ->
  env_good_bounds G1 ->
  trans_up n1 ->
  stpd2 true G1 TX (TMem TBot T2).
Proof.
  intros. repeat eu.
  assert (exists nx, stp2 true G1 (TMem TXL TXU) (TMem TBot T1) nx /\ nx <= n1) as E. eapply (stpd_inv_mem n1). eauto. eauto. omega.
  destruct E as [nx [ST X]].
  inversion ST. subst.

  assert (trans_on n3) as IH. { eapply trans_le; eauto. omega. }
  assert (stpd2 true G1 TXU T2) as ST1. { eapply IH. eauto. eauto. }
  destruct ST1.
  eapply stpd_build_mem. eauto. eauto. eauto. eapply stp2_mem. eauto. eauto. eauto.
Qed.

(* need to invert mem. requires proper realizability evidence *)
Lemma stpde_trans_cross: forall G1 TX T1 T2 TXL TXU n1 n2 n,
                          (* trans_on *)
  stp2 true G1 TX (TMem T1 TTop) n1 ->
  stpd2 true G1 TX (TMem TBot T2) ->
  exp G1 TX (TMem TXL TXU) ->
  stp2 true G1 TXL TXU n2 ->
  trans_up n ->
  n2 <= n ->
  n1 <= n ->
  stpd2 true G1 T1 T2.
Proof.
  intros. eu.
  assert (exists n3, stp2 true G1 (TMem TXL TXU) (TMem T1 TTop) n3 /\ n3 <= n1) as SM1. eapply (stpd_inv_mem n1). eauto. eauto. omega.
  assert (exists n3, stp2 true G1 (TMem TXL TXU) (TMem TBot T2) n3 /\ n3 <= x) as SM2. eapply (stpd_inv_mem x). eauto. eauto. omega.
  destruct SM1 as [n3 [SM1 E3]].
  destruct SM2 as [n4 [SM2 E4]].
  inversion SM1. inversion SM2.
  subst. clear SM1 SM2.
  
  assert (trans_on n0) as IH0. { eapply trans_le; eauto. omega. }
  assert (trans_on n2) as IH1. { eapply trans_le; eauto. }
  eapply IH0. eauto. eapply IH1. eauto. eauto. 
Qed.

(* ----- end expansion  ----- *)



(* -- trans helpers: based on imp *)


(* if a type is realizable, it expands *)
Lemma itp_exp_internal: forall n G1, forall T1 TL TU n1 n3,
  n1 <= n ->
  itp2 G1 T1 n1 ->
  stp2 true G1 T1 (TMem TL TU) n3 ->
  exists TL1 TU1 n4 n5 n6,
    exp G1 T1 (TMem TL1 TU1) /\
    stp2 true G1 TL1 TU1 n5 /\
    stp2 true G1 (TMem TL1 TU1) (TMem TL TU) n6 /\
    itp2 G1 TU1 n4 /\
    n4 <= n /\
    n5 <= n3 /\
    n6 <= n3.
Proof.
  intros n1 G1.
  induction n1.
  Case "z". intros. inversion H; subst. inversion H0; subst; inversion H1. subst.
  Case "S n". intros. inversion H0; subst; inversion H1. subst.
  - SCase "mem".
    repeat eexists. eapply exp_mem. eauto. eauto. eauto. omega. omega. omega.
  - SCase "sel".
    index_subst.

    (* first half *)
    assert (n2 <= n1) as E. omega.
    assert (exists TL1 TU1 n4 n5 n6,
              exp G1 TX0 (TMem TL1 TU1) /\
              stp2 true G1 TL1 TU1 n5 /\
              stp2 true G1 (TMem TL1 TU1) (TMem TBot (TMem TL TU)) n6 /\
              itp2 G1 TU1 n4 /\
              n4 <= n1 /\
              n5 <= n0 /\
              n6 <= n0
           ) as IH. { eapply IHn1. apply E. eauto. eauto. }
    repeat destruct IH as [? IH].

    (* obtain stp for second half input *)
    assert (exists n, stp2 true G1 (TMem x0 x1) (TMem TBot (TMem TL TU)) n /\ n <= n0) as IX.
    { eauto. }
    repeat destruct IX as [? IX]. inversion H13. subst.

    
    assert (exists TL1 TU1 n4' n5' n6',
              exp G1 x1 (TMem TL1 TU1) /\
              stp2 true G1 TL1 TU1 n5' /\
              stp2 true G1 (TMem TL1 TU1) (TMem TL TU) n6' /\
              itp2 G1 TU1 n4' /\
              n4' <= n1 /\
              n5' <= n6 /\
              n6' <= n6
           ) as IH2. { eapply IHn1. apply H11. eauto. eauto. } 
    repeat destruct IH2 as [? IH2].
    repeat eexists. index_subst.
    eapply exp_sel. eauto. eauto. eauto. eauto. eauto. eauto. omega. omega. omega.
Qed.


Lemma itp_exp: forall G1 T1 TL TU n1 n2,
  itp2 G1 T1 n1 ->
  stp2 true G1 T1 (TMem TL TU) n2 ->
  exists TL1 TU1, exp G1 T1 (TMem TL1 TU1).
Proof.
  intros.
  assert (exists TL1 TU1 n4 n5 n6,
            exp G1 T1 (TMem TL1 TU1) /\
            stp2 true G1 TL1 TU1 n5 /\
            stp2 true G1 (TMem TL1 TU1) (TMem TL TU) n6 /\
            itp2 G1 TU1 n4 /\
            n4 <= n1 /\
            n5 <= n2 /\
            n6 <= n2
         ) as HH. eapply itp_exp_internal; eauto.
  repeat destruct HH as [? HH].
  repeat eexists. eauto.
Qed.

(* need to invert mem. requires proper realizability evidence *)
Lemma stpd_trans_cross: forall G1 TX T1 T2 n1 n2 n,
  stp2 true G1 TX (TMem T1 TTop) n1 ->
  stpd2 true G1 TX (TMem TBot T2) ->
  itp2 G1 TX n2 ->
  n1 <= n ->
  trans_up n ->
  stpd2 true G1 T1 T2.
Proof.
  intros. eu.
  assert (exists TL1 TU1, exists TL TU n4 n5 n6,
            exp G1 TX (TMem TL TU) /\
            stp2 true G1 TL TU n5 /\
            stp2 true G1 (TMem TL TU) (TMem TL1 TU1) n6 /\
            itp2 G1 TU n4 /\
            n4 <= n2 /\
            n5 <= n1 /\
            n6 <= n1
         ) as HH. { eexists. eexists. eapply itp_exp_internal; eauto. }
  repeat destruct HH as [? HH].

  eapply stpde_trans_cross; eauto. omega.
Qed.







Lemma stpd_trans_hi: forall G1 T1 T2 TX n1 n2,
  stpd2 true G1 T1 T2 ->                     
  stp2 true G1 TX (TMem TBot T1) n1 ->
  itp2 G1 TX n2 ->
  trans_up n1 ->
  stpd2 true G1 TX (TMem TBot T2).
Proof.
  intros. eu.
  generalize dependent T1.
  generalize dependent T2.
  generalize dependent x.
  generalize dependent n1.
  induction H1; intros.
  - inversion H0.
  - inversion H0.
  - Case "mem".
    inversion H0. subst.
    assert (trans_on n5) as IH. { eapply trans_le; eauto. omega. }
    eapply stpd2_mem. eauto. eauto. eapply IH. eauto. eauto.
  - Case "bind".
    inversion H3.
  - Case "sel".
    inversion H3. subst. index_subst.
    assert (trans_up n2) as IH. { unfold trans_up. intros. eapply trans_le; eauto. omega. }
    eapply stpd2_sel1. eauto. eauto.
    + eapply IHitp. eauto. 
      (* arg: (TMem TBot T1) <: (TMem TBot T2) *)
      eapply stp2_mem. eapply stp2_wrapf. eapply stp2_bot. eapply stp2_bot. eapply H0. eapply H7.
Grab Existential Variables. apply 0. apply 0.
Qed.


Inductive trivial_stp: ty -> ty -> Prop :=
| trivial_mem: forall T1 T2,
    trivial_stp (TMem T1 TTop) (TMem T2 TTop)
| trivial_nest: forall T1 T2,
    trivial_stp T1 T2 ->
    trivial_stp (TMem TBot T1) (TMem TBot T2).

(* TODO: should be able to do this without itp *)
(* by induction on TX < T1 *)
Lemma stpd_trans_triv: forall G1 T1 T2 TX n2,
  trivial_stp T1 T2 ->
  stpd2 true G1 T1 T2 ->                     
  stpd2 true G1 TX T1 ->
  itp2 G1 TX n2 ->
  stpd2 true G1 TX T2.
Proof.
  intros. eu.
  generalize dependent T1.
  generalize dependent T2.
  generalize dependent x.
  induction H2; intros.
  - inversion H; subst; inversion H1.
  - inversion H; subst; inversion H1.
  - Case "mem".
    (* remember (TMem TL TU) as TX.
    generalize dependent TX. *)
    induction H.
    + SCase "trivial mem".
      inversion H0. inversion H1. subst. inversion H. subst.
      eapply stpd2_mem. eapply stp0f2_trans. eauto. eauto. eauto. eauto. eauto.
    + SCase "trivial nest".
      inversion H0. inversion H1. subst. inversion H3. subst.
      eapply stpd2_mem. eauto. eauto. eapply IHitp. eauto. eauto. eauto.
  - Case "bind".
    inversion H0; subst; inversion H3.
  - Case "sel".
    inversion H0.
    + SCase "trivial mem". subst.
      inversion H3. subst. index_subst.
      eapply stpd2_sel1. eauto. eauto. eapply IHitp. eauto. eapply trivial_nest. eauto.
      eapply stpd2_mem. eauto. eauto. eauto. eauto.
    + SCase "trivial nest". subst.
      inversion H3. subst. index_subst.
      eapply stpd2_sel1. eauto. eauto. eapply IHitp. eauto. eapply trivial_nest. eauto.
      eapply stpd2_mem. eauto. eauto. eauto. eauto.
Grab Existential Variables. apply 0. apply 0. apply 0. apply 0.
Qed.



Lemma stpd_trans_lo: forall G1 T1 T2 TX n2,
  stpd2 true G1 T1 T2 ->                     
  stpd2 true G1 TX (TMem T2 TTop) ->
  itp2 G1 TX n2 ->
  stpd2 true G1 TX (TMem T1 TTop).
Proof.
  intros. eapply stpd_trans_triv. eapply trivial_mem.
  eapply stpd2_mem. eapply stpd2_wrapf. eauto. eauto. eauto. eauto. eauto.
  Grab Existential Variables. apply 0. apply 0.
Qed.


(* proper trans lemma *)
Lemma stp2_trans: forall n, trans_up n.
Proof.
  intros n. induction n. {
    Case "z".
    unfold trans_up. intros n1 NE1 b G1 T1 T2 T3 S12 S23.
    destruct S23 as [? S23].
    inversion NE1. subst n1.
    inversion S12; subst.
    - SCase "Bot < ?". eapply stpd2_bot.
    - SCase "? < Top". inversion S23; subst.
      + SSCase "Top". eauto.
      + SSCase "Sel2".
        assert (index x0 G1 = Some TX). eauto.
        (* eapply IMP in H. destruct H. subst. *)
        eapply stpd2_sel2. eauto. eauto. eapply stpd_trans_lo; eauto.
    - SCase "Bool < Bool". eauto.
  }
  
  Case "S n".
  unfold trans_up. intros n1 NE1 b G1 T1 T2 T3 S12 S23.
  destruct S23 as [n2 S23].

  stp_cases(inversion S12) SCase. 
  - SCase "Bot < ?". eapply stpd2_bot.
  - SCase "? < Top". subst. inversion S23; subst.
    + SSCase "Top". eapply stpd2_top.
    + SSCase "Sel2".
      assert (itpd G1 TX) as E. eauto. destruct E as [? E].
      eapply itp_exp in E; eauto.
      eapply stpd2_sel2; eauto. eauto. eapply stpd_trans_lo; eauto.
  - SCase "Bool < Bool". inversion S23; subst; try solve by inversion.
    + SSCase "Top". eauto.
    + SSCase "Bool". eapply stpd2_bool; eauto.
    + SSCase "Sel2". eapply stpd2_sel2. eauto. eauto. eexists. eapply H6. 
  - SCase "Fun < Fun". inversion S23; subst; try solve by inversion.
    + SSCase "Top". eapply stpd2_top.
    + SSCase "Fun". inversion H10. subst.
      eapply stpd2_fun.
      * eapply stp0f2_trans; eauto.
      * assert (trans_on n3) as IH.
        { eapply trans_le; eauto. omega. }
        eapply IH; eauto.
    + SSCase "Sel2".
      assert (itpd G1 TX) as E. eauto. destruct E as [? E].
      eapply itp_exp in E; eauto.
      eapply stpd2_sel2. eauto. eauto. eapply stpd_trans_lo; eauto.
  - SCase "Mem < Mem". inversion S23; subst; try solve by inversion.
    + SSCase "Top". eapply stpd2_top.
    + SSCase "Mem". inversion H12. subst.
      eapply stpd2_mem.
      * eapply stp0f2_trans; eauto.
      * eauto. 
      * assert (trans_on n4) as IH.
        { eapply trans_le; eauto. omega. }
        eapply IH; eauto.
    + SSCase "Sel2". 
      assert (itpd G1 TX) as E. eauto. destruct E as [? E].
      eapply itp_exp in E; eauto.
      eapply stpd2_sel2. eauto. eauto. eapply stpd_trans_lo; eauto.
  - SCase "? < Sel". inversion S23; subst; try solve by inversion.
    + SSCase "Top". eapply stpd2_top.
    + SSCase "Sel2". 
      assert (itpd G1 TX) as E. eauto. destruct E as [? E].
      eapply itp_exp in E; eauto.
      eapply stpd2_sel2. eauto. eauto. eapply stpd_trans_lo; eauto.
    + SSCase "Sel1". (* interesting case *)
      index_subst.
      assert (itpd G1 TX) as E. eauto. destruct E as [? E].
      eapply itp_exp in E; eauto.
      inversion H12. subst. index_subst. eauto. eapply stpd_trans_cross; eauto. 
      assert (trans_up n0) as IH. 
      { unfold trans_up. intros. apply IHn. omega. }
      apply IH.
    + SSCase "Selx". inversion H9. index_subst. subst. index_subst. subst.
      eapply stpd2_sel2. eauto. eauto. eauto.
  - SCase "Sel < ?".
      assert (trans_up n0) as IH.
      { unfold trans_up. intros. eapply IHn. omega. }
      assert (itpd G1 TX) as E. eauto. destruct E as [? E].
      eapply itp_exp in E; eauto.
      eapply stpd2_sel1. eauto. eauto. eapply stpd_trans_hi; eauto. 
  - SCase "Sel < Sel". inversion S23; subst; try solve by inversion.
    + SSCase "Top". eapply stpd2_top.
    + SSCase "Sel2". 
      assert (itpd G1 TX) as E. eauto. destruct E as [? E].
      eapply itp_exp in E; eauto.
      (* eapply stpd_sel2. eauto. eapply stpd_trans_lo; eauto. *)
    + SSCase "Sel1". inversion H9. index_subst. subst. index_subst. subst.
      eapply stpd2_sel1. eauto. eauto. eauto.
    + SSCase "Selx". inversion H6. subst. repeat index_subst.
      eapply stpd2_selx; eauto.
  - SCase "Bind < Bind". inversion S23; subst; try solve by inversion.
    + SSCase "Top". eapply stpd2_top.
    + SSCase "Sel2". 
      assert (itpd G1 TX) as E. eauto. destruct E as [? E].
      eapply itp_exp in E; eauto.
      eapply stpd2_sel2. eauto. eauto. eapply stpd_trans_lo; eauto.
    + SSCase "Bind".
      inversion H12. subst.
      assert (stpd false ((length G1, open (length G1) TA1) :: G1)
                   (open (length G1) TA2) (open (length G1) TA3)) as NRW.
      { 
        assert (beq_nat (length G1) (length G1) = true) as E.
        { eapply beq_nat_true_iff. eauto. }
        inversion H12. subst.
        eapply stp_narrow. eauto. eauto.
        instantiate (2 := length G1). unfold index. rewrite E. eauto.
        instantiate (1 := open (length G1) TA1). unfold update. rewrite E. eauto.
        eauto.
      }
      eapply stpd2_bindx. eapply stp0f_trans. eapply H. eapply NRW. eauto.
      eauto. eauto.
  - SCase "Trans". subst.
    assert (trans_on n3) as IH2.
    { eapply trans_le; eauto. omega. }
    assert (trans_on n0) as IH1.
    { eapply trans_le; eauto. omega. }
    assert (stpd2 true G1 T4 T3) as S123.
    { eapply IH2; eauto. }
    destruct S123.
    eapply IH1; eauto.
  - SCase "Wrap". subst.
    assert (trans_on n0) as IH.
    { eapply trans_le; eauto. omega. }
    eapply IH; eauto.
Qed.


(* convert stp false to stp2 false, and then to stp2 true *)

Lemma stp2_untrans: forall n, forall G1 T1 T2 n0,
  stp2 false G1 T1 T2 n0 ->
  n0 <= n ->
  stpd2 true G1 T1 T2.
Proof.
  intros n. induction n.
  - Case "z".
    intros. inversion H; inversion H0; subst; eauto; try solve by inversion.
  - Case "s n".
    intros. inversion H; subst.
    + SCase "transf". eapply stp2_trans.
      instantiate (2 := n1).
      instantiate (1 := n1).
      eauto. eapply H1. eapply IHn. eauto. omega. 
    + SCase "wrapf". eauto.
Qed.

Lemma stp_convert: forall n, forall m G1 T1 T2 n0,
  stp m G1 T1 T2 n0 ->
  n0 <= n ->
  env_itp G1 ->
  stpd2 m G1 T1 T2.
Proof.
  intros n.
  induction n.
  - Case "z".
    intros. inversion H; inversion H0; subst; eauto; try solve by inversion.
  - Case "s n".
    intros.
    inversion H.
    + SCase "bot". eauto.
    + SCase "top". eauto.
    + SCase "bool". eauto.
    + SCase "fun". eapply stpd2_fun. eapply IHn; eauto. omega. eapply IHn; eauto. omega.
    + SCase "mem". eapply stpd2_mem. eapply IHn; eauto. omega. eapply IHn; eauto. omega. eapply IHn; eauto. omega.
    + SCase "sel2".
      assert (stpd2 false G1 TX (TMem T1 TTop)) as ST. { eapply IHn; eauto. omega. }
      assert (stpd2 true G1 TX (TMem T1 TTop)). { destruct ST. eapply stp2_untrans; eauto. } 
      assert (itpd2 G1 TX). { eapply H1; eauto. } (* from env_itp *)
      eapply stpd2_sel2; eauto.
    + SCase "sel1".
      assert (stpd2 false G1 TX (TMem TBot T2)) as ST. { eapply IHn; eauto. omega. }
      assert (stpd2 true G1 TX (TMem TBot T2)). { destruct ST. eapply stp2_untrans; eauto. } (* un-trans *)
      assert (itpd2 G1 TX). { eapply H1; eauto. } (* from env_itp *)
      eapply stpd2_sel1; eauto.
    + SCase "selx".
      eapply stpd2_selx; eauto.
    + SCase "bindx".
      eapply stpd2_bindx; eauto.
    + SCase "transf".
      eapply stpd2_transf. eapply IHn; eauto. omega. eapply IHn; eauto. omega.
    + SCase "wrapf".
      eapply stpd2_wrapf. eapply IHn; eauto. omega.
Grab Existential Variables. apply 0. apply 0. apply 0. apply 0. apply 0. apply 0. apply 0.
Qed.

(* ----------- stp3 code --------- *)


Definition trans_on3 n2 :=
  forall m G1 T1 T2 T3,
      stp3 m G1 T1 T2 n2 ->
      stpd3 true G1 T2 T3 ->
      stpd3 true G1 T1 T3.

Hint Unfold trans_on3.


Definition trans_up3 n := forall n1, n1 <= n ->
                      trans_on3 n1.
Hint Unfold trans_up3.

Lemma trans_le3: forall n n1,
                      trans_up3 n ->
                      n1 <= n ->
                      trans_on3 n1
.
Proof. intros. unfold trans_up3 in H. eapply H. eauto. Qed.



Lemma stpd3_trans_hi: forall G1 T1 T2 TX n1 n2,
  stpd3 true G1 T1 T2 ->                     
  stp3 true G1 TX (TMem TBot T1) n1 ->
  itp3 G1 TX n2 ->
  trans_up3 n1 ->
  stpd3 true G1 TX (TMem TBot T2).
Proof.
  admit.
Qed.

Lemma stpd3_trans_lo: forall G1 T1 T2 TX n2,
  stpd3 true G1 T1 T2 ->                     
  stpd3 true G1 TX (TMem T2 TTop) ->
  itp3 G1 TX n2 ->
  stpd3 true G1 TX (TMem T1 TTop).
Proof.
  admit.
Qed.

Lemma itp3_exp: forall G1 T1 TL TU n1 n2,
  itp3 G1 T1 n1 ->
  stp3 true G1 T1 (TMem TL TU) n2 ->
  exists TL1 TU1, exp G1 T1 (TMem TL1 TU1).
Proof.
  admit.
Qed.

Lemma stpd3_trans_cross: forall G1 TX T1 T2 n1 n2 n,
  stp3 true G1 TX (TMem T1 TTop) n1 ->
  stpd3 true G1 TX (TMem TBot T2) ->
  itp3 G1 TX n2 ->
  n1 <= n ->
  trans_up3 n ->
  stpd3 true G1 T1 T2.
Proof.
  admit.
Qed.


  (* proper trans lemma *)
Lemma stp3_trans: forall n, trans_up3 n.
Proof.
(*
  intros n. induction n. {
    Case "z".
    unfold trans_up3. intros n1 NE1 b G1 T1 T2 T3 S12 S23.
    destruct S23 as [? S23].
    inversion NE1. subst n1.
    inversion S12; subst.
    - SCase "Bot < ?". eapply stpd3_bot.
    - SCase "? < Top". inversion S23; subst.
      + SSCase "Top". eauto.
      + SSCase "Sel2".
        assert (index x0 G1 = Some TX). eauto.
        (* eapply IMP in H. destruct H. subst. *)
        eapply stpd3_sel2. eauto. eauto. eapply stpd3_trans_lo; eauto.
    - SCase "Bool < Bool". eauto.
  }
  
  Case "S n".
  unfold trans_up3. intros n1 NE1 b G1 T1 T2 T3 S12 S23.
  destruct S23 as [n2 S23].

  stp_cases(inversion S12) SCase. 
  - SCase "Bot < ?". eapply stpd3_bot.
  - SCase "? < Top". subst. inversion S23; subst.
    + SSCase "Top". eapply stpd3_top.
    + SSCase "Sel2".
      assert (itpd G1 TX) as E. eauto. destruct E as [? E].
      eapply itp3_exp in E; eauto.
      eapply stpd3_sel2; eauto. eauto. eapply stpd3_trans_lo; eauto.
  - SCase "Bool < Bool". inversion S23; subst; try solve by inversion.
    + SSCase "Top". eauto.
    + SSCase "Bool". eapply stpd3_bool; eauto.
    + SSCase "Sel2". eapply stpd3_sel2. eauto. eauto. eexists. eapply H6. 
  - SCase "Fun < Fun". inversion S23; subst; try solve by inversion.
    + SSCase "Top". eapply stpd3_top.
    + SSCase "Fun". inversion H10. subst.
      eapply stpd3_fun.
      * eapply stp0f2_trans; eauto.
      * eapply stp2_trans. instantiate (1:=n3). eauto. eauto. eauto.
    + SSCase "Sel2".
      assert (itpd3 G1 TX) as E. eauto. destruct E as [? E].
      eapply itp3_exp in E; eauto.
      eapply stpd3_sel2. eauto. eauto. eapply stpd3_trans_lo; eauto.
  - SCase "Mem < Mem". inversion S23; subst; try solve by inversion.
    + SSCase "Top". eapply stpd3_top.
    + SSCase "Mem". inversion H10. subst.
      eapply stpd3_mem.
      * eapply stp0f2_trans; eauto.
      * assert (trans_on3 n3) as IH.
        { eapply trans_le3; eauto. omega. }
        eapply IH; eauto.
    + SSCase "Sel2". 
      assert (itpd G1 TX) as E. eauto. destruct E as [? E].
      eapply itp3_exp in E; eauto.
      eapply stpd3_sel2. eauto. eauto. eapply stpd3_trans_lo; eauto.
  - SCase "? < Sel". inversion S23; subst; try solve by inversion.
    + SSCase "Top". eapply stpd3_top.
    + SSCase "Sel2". 
      assert (itpd G1 TX) as E. eauto. destruct E as [? E].
      eapply itp3_exp in E; eauto.
      eapply stpd3_sel2. eauto. eauto. eapply stpd3_trans_lo; eauto.
    + SSCase "Sel1". (* interesting case *)
      index_subst.
      assert (itpd G1 TX) as E. eauto. destruct E as [? E].
      eapply itp3_exp in E; eauto.
      inversion H12. subst. index_subst. eauto. eapply stpd3_trans_cross; eauto. 
      assert (trans_up3 n0) as IH. 
      { unfold trans_up3. intros. apply IHn. omega. }
      apply IH.
    + SSCase "Selx". inversion H9. index_subst. subst. index_subst. subst.
      eapply stpd3_sel2. eauto. eauto. eauto.
  - SCase "Sel < ?".
      assert (trans_up n0) as IH.
      { unfold trans_up. intros. eapply IHn. omega. }
      assert (itpd G1 TX) as E. eauto. destruct E as [? E].
      eapply itp_exp in E; eauto.
      eapply stpd2_sel1. eauto. eauto. eapply stpd_trans_hi; eauto. 
  - SCase "Sel < Sel". inversion S23; subst; try solve by inversion.
    + SSCase "Top". eapply stpd2_top.
    + SSCase "Sel2". 
      assert (itpd G1 TX) as E. eauto. destruct E as [? E].
      eapply itp_exp in E; eauto.
      (* eapply stpd_sel2. eauto. eapply stpd_trans_lo; eauto. *)
    + SSCase "Sel1". inversion H9. index_subst. subst. index_subst. subst.
      eapply stpd2_sel1. eauto. eauto. eauto.
    + SSCase "Selx". inversion H6. subst. repeat index_subst.
      eapply stpd2_selx; eauto.
  - SCase "Bind < Bind". inversion S23; subst; try solve by inversion.
    + SSCase "Top". eapply stpd2_top.
    + SSCase "Sel2". 
      assert (itpd G1 TX) as E. eauto. destruct E as [? E].
      eapply itp_exp in E; eauto.
      eapply stpd2_sel2. eauto. eauto. eapply stpd_trans_lo; eauto.
    + SSCase "Bind".
      inversion H12. subst.
      assert (stpd false ((length G1, open (length G1) TA1) :: G1)
                   (open (length G1) TA2) (open (length G1) TA3)) as NRW.
      { 
        assert (beq_nat (length G1) (length G1) = true) as E.
        { eapply beq_nat_true_iff. eauto. }
        inversion H12. subst.
        eapply stp_narrow. eauto. eauto.
        instantiate (2 := length G1). unfold index. rewrite E. eauto.
        instantiate (1 := open (length G1) TA1). unfold update. rewrite E. eauto.
        eauto.
      }
      eapply stpd2_bindx. eapply stp0f_trans. eapply H. eapply NRW. eauto.
      eauto. eauto.
  - SCase "Trans". subst.
    assert (trans_on n3) as IH2.
    { eapply trans_le; eauto. omega. }
    assert (trans_on n0) as IH1.
    { eapply trans_le; eauto. omega. }
    assert (stpd2 true G1 T4 T3) as S123.
    { eapply IH2; eauto. }
    destruct S123.
    eapply IH1; eauto.
  - SCase "Wrap". subst.
    assert (trans_on n0) as IH.
    { eapply trans_le; eauto. omega. }
    eapply IH; eauto.
 *)
  admit.
Qed.


Lemma stp3_untrans: forall n, forall G1 T1 T2 n0,
  stp3 false G1 T1 T2 n0 ->
  n0 <= n ->
  stpd3 true G1 T1 T2.
Proof.
  intros n. induction n.
  - Case "z".
    intros. inversion H; inversion H0; subst; eauto; try solve by inversion.
  - Case "s n".
    intros. inversion H; subst.
    + SCase "transf". eapply stp3_trans.
      instantiate (2 := n1).
      instantiate (1 := n1).
      eauto. eapply H1. eapply IHn. eauto. omega. 
    + SCase "wrapf". eauto.
Qed.

Lemma itp_widen: forall G1 T1 T2 n1,
  itp3 G1 T1 n1 ->
  stpd3 true G1 T1 T2 ->
  itpd3 G1 T2.
Proof. admit. Qed.

Lemma stp_convert3: forall n, forall m G1 T1 T2 n0 n1,
  itp3 G1 T1 n1 ->
  stp m G1 T1 T2 n0 ->
  n0 <= n ->
  env_itp G1 ->
  stpd3 m G1 T1 T2.
Proof.
  intros n.
  induction n.
  - Case "z".
    intros. inversion H0; inversion H1; subst; eauto; try solve by inversion.
  - Case "s n".
    intros.
    inversion H0.
    + SCase "bot". eauto.
    + SCase "top". eauto.
    + SCase "bool". eauto.
    + SCase "fun". eapply stpd3_fun. eapply stp_convert; eauto. eapply stp_convert; eauto.
    + SCase "mem". eapply stpd3_mem. eapply stp_convert; eauto. subst. inversion H. subst. eapply IHn; eauto. omega. 
    + SCase "sel2".
      assert (itpd3 G1 TX). { eapply H2; eauto. } (* from env_itp *)
      assert (stpd3 true G1 TX (TMem T1 TTop)) as ST. { eu. eapply IHn; eauto. omega. }
      eapply stpd3_sel2; eauto.
    + SCase "sel1".
      assert (itpd3 G1 TX). { eapply H2; eauto. } (* from env_itp *)
      assert (stpd3 true G1 TX (TMem TBot T2)) as ST. { eu. eapply IHn; eauto. omega. }
      eapply stpd3_sel1; eauto.
    + SCase "selx".
      eapply stpd3_selx; eauto.
    + SCase "bindx".
      eapply stpd3_bindx. subst. inversion H. subst.
      eapply IHn. eauto. eauto. omega. eapply env_itp_extend; eauto. subst. eauto. subst. eauto.
      subst. inversion H. subst. eauto.
    + SCase "transf".
      assert (itpd3 G1 T3). { eapply itp_widen; eauto.  eapply IHn; eauto. omega. } eu.
      assert (stpd3 false G1 T1 T2). eapply stpd3_transf. eapply IHn; eauto. omega. eapply stpd3_wrapf. eapply IHn; eauto. omega. eu.
      eapply stp3_untrans; eauto.
    + SCase "wrapf".
      eapply IHn; eauto. omega.
Grab Existential Variables. apply 0. apply 0. apply 0. apply 0. apply 0. apply 0. apply 0.
Qed.






End DOT.

