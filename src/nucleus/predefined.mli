val predefined_aml_types : string
val predefined_ops : string

val operation_equal : Runtime.value -> Runtime.value -> Runtime.value Runtime.comp

val operation_as_prod : Runtime.value -> Runtime.value Runtime.comp
val operation_as_eq : Runtime.value -> Runtime.value Runtime.comp
val operation_as_signature : Runtime.value -> Runtime.value Runtime.comp

val as_list : loc:Location.t -> Runtime.value -> Runtime.value list
val mk_list : Runtime.value list -> Runtime.value

(** Wrappers for making tags *)
val from_option : Runtime.value option -> Runtime.value
val as_option : loc:Location.t -> Runtime.value -> Runtime.value option

val from_constrain : (Runtime.value,Runtime.value) Tt.constrain -> Runtime.value
val as_constrain : loc:Location.t -> Runtime.value -> (Runtime.value, Runtime.value) Tt.constrain

