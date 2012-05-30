(** The Boolean algebra generated by open and closed intervals. *)

module Region = 
  functor (D : Dyadic.DYADIC) ->
    struct
 
    module I = Interval.Interval(D)

    type endpoint = 
      | NegativeInfinity
      | PositiveInfinity
      | Open of D.t
      | Closed of D.t

    type segment = endpoint * endpoint

    (** The segments in a region are disjoint and ordered *)
    type region = segment list

    let string_of_left_endpoint = function
      | NegativeInfinity -> "(-inf"
      | Open q -> "(" ^ D.to_string q
      | Closed q -> "[" ^ D.to_string q
      | PositiveInfinity -> assert false

    let string_of_right_endpoint = function
      | NegativeInfinity -> assert false
      | Open q -> D.to_string q ^ ")"
      | Closed q -> D.to_string q ^ "]"
      | PositiveInfinity -> "+inf)"

    let string_of_segment (a,b) = string_of_left_endpoint a ^ "," ^ string_of_right_endpoint b

    let to_string = function
      | [] -> "{}"
      | lst -> String.concat ", " (List.map string_of_segment lst)

    let empty = []

    let real_line_segment = (NegativeInfinity, PositiveInfinity)

    let real_line = [real_line_segment]

    let closed_of_dyadic a =
      match D.classify a with
	| `number -> Closed a
	| `nan -> raise (Invalid_argument "Region.closed_of_dyadic")
	| `negative_infinity -> NegativeInfinity
	| `positive_infinity -> PositiveInfinity

    let dyadic_of_endpoint = function
      | NegativeInfinity -> D.negative_infinity
      | PositiveInfinity -> D.positive_infinity
      | Open q | Closed q -> q

    let of_interval i =
      let a = I.lower i in
      let b = I.upper i in
	if D.leq a b then
	  [(closed_of_dyadic a, closed_of_dyadic b)]
	else
	  raise (Invalid_argument "Region.of_interval")

    let lower (p, _) = p
    let upper (_, q) = q

    let open_segment a b = [(Open a, Open b)]
    let closed_segment a b = [(Closed a, Closed b)]

    let open_left_ray a = [(NegativeInfinity, Open a)]
    let open_right_ray a = [(Open a, PositiveInfinity)]

    let closed_left_ray a = [(NegativeInfinity, Closed a)]
    let closed_right_ray a = [(Closed a, PositiveInfinity)]

    let negative_one = D.negative_one

    (* Midpoint of a closed segment. *)
    let midpoint = function
      | NegativeInfinity, PositiveInfinity -> D.zero
      | (Open q | Closed q), PositiveInfinity ->
	  if D.lt q D.one then D.one else
	    D.double ~round:D.up q
      | NegativeInfinity, (Open q | Closed q) ->
	  if D.gt q negative_one then
	    negative_one
	  else
	    D.double ~round:D.down q
      | (Open q1 | Closed q1), (Open q2 | Closed q2) ->
	  D.average q1 q2
	    
      | PositiveInfinity, _ | _, NegativeInfinity -> raise (Invalid_argument "Region.midpoint")

    let split i =
      let m = midpoint i in
	(fst i, Closed m), (Closed m, snd i)

    let interval_of_segment (a,b) =
      I.make (dyadic_of_endpoint a) (dyadic_of_endpoint b)

    let touch p1 p2 =
      match p1, p2 with
	| Open p, Closed q
	| Closed p, Open q -> D.eq p q
	| _, _ -> false

    let rec normalize = function
      | [] -> []
      | [s] -> [s]
      | (a,b)::(b',c)::r when touch b b' -> normalize ((a,c)::r)
      | s::r -> s::(normalize r)

    let cmp ?(direction=`right) p1 p2 =
      match p1, p2 with
	| NegativeInfinity, NegativeInfinity -> `equal
	| NegativeInfinity, _ -> `less
	| _, NegativeInfinity -> `greater
	| PositiveInfinity, PositiveInfinity -> `equal
	| _, PositiveInfinity -> `less
	| PositiveInfinity, _ -> `greater
	| Open p, Open q -> D.cmp p q
	| Closed p, Closed q -> D.cmp p q
	| Open p, Closed q ->
	    (match D.cmp p q with
	      | `less -> `less
	      | `equal -> (match direction with `left -> `greater | `right -> `less)
	      | `greater -> `greater)
	| Closed p, Open q ->
	    (match D.cmp p q with
	      | `less -> `less
	      | `equal -> (match direction with `left -> `less | `right -> `greater)
	      | `greater -> `greater)

    let min_point ?direction p1 p2 =
      match cmp ?direction p1 p2 with
	| `less | `equal -> p1
	| `greater -> p2

    let max_point ?direction p1 p2 =
      match cmp ?direction p1 p2 with
	| `less | `equal -> p2
	| `greater -> p1

    let lt ?direction p1 p2 = (cmp ?direction p1 p2) = `less

    let leq ?direction p1 p2 = (cmp ?direction p1 p2) <> `greater

    let is_interval a b =
      match a, b with
	| _, NegativeInfinity | PositiveInfinity, _ -> false
	| NegativeInfinity, (Open _ | Closed _ | PositiveInfinity)
	| (Open _ | Closed _), PositiveInfinity -> true
	| Open p, Open q -> D.cmp p q = `less
	| Closed p, Closed q -> D.cmp p q <> `greater
	| Open p, Closed q | Closed p, Open q -> D.cmp p q = `less

    let invert_closure = function
      | NegativeInfinity | PositiveInfinity -> assert false
      | Open q -> Closed q
      | Closed q -> Open q

    let rec subseteq r1 r2 =
      match r1, r2 with
	| [], _ -> true
	| _::_, [] -> false
	| (a,b)::s1, (c,d)::s2 when leq ~direction:`left c a ->
	  (match cmp b d with
	    | `less -> subseteq s1 r2
	    | `equal -> subseteq s1 s2
	    | `greater -> subseteq ((a, invert_closure d)::s1) s2)
	| r1, _::s2 -> subseteq r1 s2

    let is_empty r = subseteq r empty

    let is_inhabited r = not (subseteq r empty)

    let rec intersection (r1:region) (r2:region) =
      match r1, r2 with
	| [], _ | _, [] -> []
	| i::is, j::js ->
	    let il = lower i in
	    let iu = upper i in
	    let jl = lower j in
	    let ju = upper j in
	    let s =
	      intersection
		(if lt ju iu then r1 else is)
		(if lt iu ju then r2 else js)
	    in
	    let kl = max_point ~direction:`left il jl in
	    let ku = min_point iu ju in
	      if is_interval kl ku then (kl, ku) :: s else s

    let rec union (lst1:region) (lst2:region) =
      match lst1, lst2 with
	| lst1, [] -> lst1
	| [], lst2 -> lst2
	| i::is, j::js ->
	    let il = lower i in
	    let iu = upper i in
	    let jl = lower j in
	    let ju = upper j in
	      if touch iu jl then union ((il,ju)::is) js
	      else if touch ju il then union is ((jl,iu)::js)
	      else if lt iu jl then i :: (union is lst2)
	      else if lt ju il then j :: (union lst1 js)
	      else
		let k = (min_point ~direction:`left il jl), (max_point iu ju) in
		  if lt iu ju then union is (k::js) else union (k::is) js

    let closure =
      let clos = function
	| NegativeInfinity -> NegativeInfinity
	| PositiveInfinity -> PositiveInfinity
	| Open p | Closed p -> Closed p
      in
	List.map (fun (p,q) -> (clos p, clos q))
	  
    let complement lst =
      let rec compl a = function
	| [] -> [(a, PositiveInfinity)]
	| (NegativeInfinity, PositiveInfinity)::_ -> empty
	| (NegativeInfinity, c)::r -> compl (invert_closure c) r
	| (b,PositiveInfinity)::_ -> [(a, invert_closure b)]
	| (b,c)::r -> (a, invert_closure b)::(compl (invert_closure c) r)

      in
	compl NegativeInfinity (normalize lst)

    let rec to_closed_intervals = function
      | [] -> []
      | (NegativeInfinity, Closed q) :: r -> I.make D.negative_infinity q :: (to_closed_intervals r)
      | (Closed q, PositiveInfinity) :: r -> I.make q D.positive_infinity :: (to_closed_intervals r)
      | (Closed p, Closed q) :: r -> I.make p q :: (to_closed_intervals r)
      | lst -> Message.runtime_error ("Region " ^ to_string lst ^ " is not closed")

    let infimum = function
      | [] -> D.positive_infinity
      | ((Open a|Closed a), _)::_ -> a
      | (NegativeInfinity, _)::_ -> D.negative_infinity
      | (PositiveInfinity, _)::_ -> assert false

    let rec supremum = function
      | [] -> D.negative_infinity
      | [(_, (Closed b|Open b))] -> b
      | [(_, PositiveInfinity)] -> D.positive_infinity
      | _::r -> supremum r

end;;