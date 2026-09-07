(** Pure corpus-plant evidence checks.  These execute only the reference
    interpreter; the campaign gate owns the fresh three-leg witnesses. *)

let sample (body : Ast.expr) : Sample.t =
  { Sample.mode = Taxonomy.Read_only; inputs = []; signals = [];
    target = Ast.T_f64; body }

let number (hi : int) : Ast.expr = Ast.E_lit (Ast.L_f64_bits (hi, 0))

let add () : Sample.t =
  sample (Ast.E_binary (Ast.B_add, number 0x3ff00000, number 0x40000000))

let length () : Sample.t =
  sample (Ast.E_method (Ast.E_lit (Ast.L_str "abc"), Ast.M_len, []))

let held () : Sample.t = sample (number 0x40140000)

(** Signal.increment consumes f_add and leaves its changed result in the store. *)
let increment () : Sample.t =
  {
    Sample.mode = Taxonomy.Signal_writing;
    inputs = [];
    signals = [ { Sample.id = 3; ty = Ast.T_f64; init = number 0x3ff00000 } ];
    target = Ast.T_unit;
    body = Ast.E_method (Ast.E_var 3, Ast.M_increment, []);
  }

(** A baseline row is earned from the same interpreter used by selection. *)
let row (i : int) (s : Sample.t) : Journal.line =
  let text = Obs.encode (Ref_leg.observe Ref_leg.default_config s) in
  Pipeline.row ~i ~verdict:"agree" ~r:text ~j:text ~f:text s

let selected_index (p : Campaign_plants.plant)
    (xs : (Journal.line * Sample.t) list) : int =
  Result.fold ~error:(fun _ -> -1)
    ~ok:(fun pair -> (fst pair).Journal.jl_i)
    (Campaign_plants.select p xs)

let changed_observation (p : Campaign_plants.plant) (s : Sample.t) :
    Obs.observation =
  Ref_leg.observe
    { Ref_leg.default_config with Ref_leg.ops = Campaign_plants.ops p } s

let changed_value (p : Campaign_plants.plant) (s : Sample.t) : string option =
  Differ.value_of (changed_observation p s).Obs.outcome

let signal_value (id : int) (obs : Obs.observation) : string option =
  Option.map Obs.encode_value (List.assoc_opt id obs.Obs.signals)

let local_verdict (p : Campaign_plants.plant) (s : Sample.t) : Differ.verdict =
  let base = Ref_leg.observe Ref_leg.default_config s in
  Differ.verdict s.Sample.mode (Known.allow ())
    {
      Differ.rust = Differ.Present base;
      js = Differ.Present base;
      reference = Differ.Present (changed_observation p s);
    }

let is_number (hi : int) (value : string option) : bool =
  Option.fold ~none:false
    ~some:(String.equal (Obs.encode_value (Obs.V_f64_bits (hi, 0)))) value

let checks () : (string * bool) list =
  let a = add () in
  let l = length () in
  let h = held () in
  let altered = { (row 2 a) with Journal.jl_f = "stale" } in
  let nonagree =
    { (row 2 a) with Journal.jl_verdict = "diverge:value:odd:ref" }
  in
  let writer = { a with Sample.mode = Taxonomy.Signal_writing } in
  let inc = increment () in
  let length_writer =
    { inc with Sample.body = Ast.E_method (Ast.E_var 3, Ast.M_set, [ l.Sample.body ]) }
  in
  let add_ops = Campaign_plants.ops Campaign_plants.Add_sign in
  let len_ops = Campaign_plants.ops Campaign_plants.Length_plus_one in
  [
    ( "first observable addition",
      Int.equal 7
        (selected_index Campaign_plants.Add_sign
           [ (row 1 h, h); (row 7 a, a); (row 9 a, a) ]) );
    ( "stale baseline excluded",
      Int.equal (-1) (selected_index Campaign_plants.Add_sign [ (altered, a) ]) );
    ( "nonagree excluded",
      Int.equal (-1) (selected_index Campaign_plants.Add_sign [ (nonagree, a) ]) );
    ( "writer value channel excluded",
      Int.equal (-1)
        (selected_index Campaign_plants.Add_sign [ (row 2 writer, writer) ]) );
    ( "length reached",
      Int.equal 11
        (selected_index Campaign_plants.Length_plus_one [ (row 11 l, l) ]) );
    ( "addition reaches minus three",
      is_number 0xc0080000 (changed_value Campaign_plants.Add_sign a) );
    ( "length reaches four",
      is_number 0x40100000 (changed_value Campaign_plants.Length_plus_one l) );
    ( "addition leaves length closure",
      add_ops.Interp.f_of_int == Ops.interp_ops.Interp.f_of_int );
    ( "length leaves addition closure",
      len_ops.Interp.f_add == Ops.interp_ops.Interp.f_add );
    ( "addition leaves display closure",
      add_ops.Interp.f_display == Ops.interp_ops.Interp.f_display );
    ( "length leaves display closure",
      len_ops.Interp.f_display == Ops.interp_ops.Interp.f_display );
    ( "two-way is not odd reference",
      not
        (Campaign_plants.expected_for Campaign_plants.Add_sign Taxonomy.Read_only
           (Differ.Diverge (Differ.Ch_value, Differ.Two_way))) );
    ( "JS oddity is not reference",
      not
        (Campaign_plants.expected_for Campaign_plants.Add_sign Taxonomy.Read_only
           (Differ.Diverge (Differ.Ch_value, Differ.Odd Differ.L_js))) );
    ( "class is not value",
      not
        (Campaign_plants.expected_for Campaign_plants.Add_sign Taxonomy.Read_only
           (Differ.Diverge (Differ.Ch_class, Differ.Odd Differ.L_ref))) );
    ( "baseline remains three",
      is_number 0x40080000
        (Differ.value_of (Ref_leg.observe Ref_leg.default_config a).Obs.outcome) );
    ( "increment baseline stores two",
      is_number 0x40000000
        (signal_value 3 (Ref_leg.observe Ref_leg.default_config inc)) );
    ( "increment plant stores minus two",
      is_number 0xc0000000
        (signal_value 3 (changed_observation Campaign_plants.Add_sign inc)) );
    ( "increment is a corpus witness",
      Int.equal 19
        (selected_index Campaign_plants.Add_sign [ (row 19 inc, inc) ]) );
    ( "increment reports signals two_way",
      String.equal "diverge:signals:two_way"
        (Differ.verdict_text (local_verdict Campaign_plants.Add_sign inc)) );
    ( "increment satisfies the addition mode fence",
      Campaign_plants.expected_for Campaign_plants.Add_sign
        Taxonomy.Signal_writing (local_verdict Campaign_plants.Add_sign inc) );
    ( "length cannot accept a writer signals verdict",
      not
        (Campaign_plants.expected_for Campaign_plants.Length_plus_one
           Taxonomy.Signal_writing
           (Differ.Diverge (Differ.Ch_signals, Differ.Two_way))) );
    ( "length writer really reaches the changed closure",
      String.equal "diverge:signals:two_way"
        (Differ.verdict_text
           (local_verdict Campaign_plants.Length_plus_one length_writer)) );
    ( "observable length writer remains ineligible",
      Int.equal (-1)
        (selected_index Campaign_plants.Length_plus_one
           [ (row 23 length_writer, length_writer) ]) );
    ( "addition cannot accept writer rendered divergence",
      not
        (Campaign_plants.expected_for Campaign_plants.Add_sign
           Taxonomy.Signal_writing
           (Differ.Diverge (Differ.Ch_rendered, Differ.Two_way))) );
    ( "addition cannot accept writer odd-reference split",
      not
        (Campaign_plants.expected_for Campaign_plants.Add_sign
           Taxonomy.Signal_writing
           (Differ.Diverge (Differ.Ch_signals, Differ.Odd Differ.L_ref))) );
    ( "addition cannot accept readonly signals divergence",
      not
        (Campaign_plants.expected_for Campaign_plants.Add_sign
           Taxonomy.Read_only
           (Differ.Diverge (Differ.Ch_signals, Differ.Odd Differ.L_ref))) );
    ( "increment leaves a fresh baseline unchanged",
      is_number 0x40000000
        (signal_value 3 (Ref_leg.observe Ref_leg.default_config inc)) );
  ]

let () =
  let results = checks () in
  List.iter
    (fun result ->
      print_endline ((if snd result then "ok " else "FAIL ") ^ fst result))
    results;
  exit (if List.for_all snd results then 0 else 1)
