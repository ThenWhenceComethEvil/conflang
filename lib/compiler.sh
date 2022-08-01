#!/bin/bash
#
# Requires from environment:
#  ROOT
#  TYPEOF{}
#  NODE_*
#  SECTION
#  ^-- Name of the section we're currently in. After we've iterated through a
#    pair of scopes, any keys remaining in the child should be copied over to
#    the parent. We must both copy the key:value from the scope (for semantic
#    analysis in the next phase), but also need to append the nodes themselves
#    to the parent section's .items array.



declare -- NODE=

#───────────────────────────────( symbol table )────────────────────────────────
# CURRENT:
# I think merging the trees is going to require 3-phases:
#  1. Generate symbol table for parent tree
#  2. Generate symbol table for child tree
#  3. Iterate parent symbol table stack
#     - Each name in that scope should have a matching name in the corresponding
#       child scope
#     - If a parent type is specified, the child value should match
#       - The child cannot overwrite a parent's type declaration
#     - If the child has a value, it *overwrites* the parent's value
#     - (Later) If the child has directives, they're *append* to the parent's
#       - Should probably compare if the directive/test does not currently
#         exist, so we're not duplicating.
#     - Any *additional* names in the child's scope are merged to the parent
#       - It may actually be easier to generate a completely separate resulting
#         tree, rather than moving from one to the other
#
# The third phase of this will clearly be the most difficult, and will likely
# take the place of the current semantic analysis, as we will need to do type
# checking to merge the two trees. Though maybe we fully ignore types here, and
# do a completely separate typechecking pass.
#
# 2022-07-28
# I don't actually think symbol tables are the right approach for this. We don't
# have the same sort of lexical scoping that a programming language does. There
# is not any way of referring to declared identifiers.
# It would also be nice if we could strip things down to dicts of the raw
# values:
#
# ## Top parent scope
# SCOPE_01=(
#     [global] = Type(Section, subtype: None, next: SCOPE_02),
#     [dirs]   = Type(Array, subtype: Type(String), next: None)
# )
#
# But how to handle the child's ADDITIONAL nodes that must be appended. Would
# need more information.
#  - Type
#    - kind
#    - subtype
#  - node         # name of that variable/section declaration node (e.g. NODE_1)
#  - scope        # name of nested scope to descend into (for section decls)

declare -A DEFAULT_TYPES=(
   [int]='INTEGER'
   [str]='STRING'
   [bool]='BOOLEAN'
   [path]='PATH'
   [array]='ARRAY'
)


# Dict(s) of name -> Type mappings... and other information.
declare -- SCOPE=
declare -i SCOPE_NUM=${SCOPE_NUM:-0}

function mk_scope {
   (( SCOPE_NUM++ ))
   # A scope maps the string identifier names to a Symbol, containing Type
   # information, as well as references to the current node, and nested (?)
   # scopes.

   local   --  sname="SCOPE_${SCOPE_NUM}"
   declare -gA $sname
   declare -g  SCOPE=$sname
   local   -n  scope=$sname
   scope=()
}


declare -- TYPE=
declare -i TYPE_NUM=${TYPE_NUM:-0}

function mk_type {
   (( TYPE_NUM++ ))
   local   --  tname="TYPE_${TYPE_NUM}"
   declare -gA $tname
   declare -g  TYPE=$tname
   local   --  type=$tname

   type[kind]=
   type[subtype]=
}


declare -- SYMBOL=
declare -i SYMBOL_NUM=${TYPE_NUM:-0}

function mk_symbol {
   (( SYMBOL_NUM++ ))
   local   --  sname="SYMBOL_${SYMBOL_NUM}"
   declare -gA $sname
   declare -g  SYMBOL=$sname
   local   --  symbol=$sname

   symbol[type]=
   symbol[node]=
   symbol[scope]=
   symbol[required]=
   # Variable declaration symbols are `required' if its NODE has no expression.
   # A Section is considered to be `required' if *any* of its children are
   # required. This is only needed when enforcing constraints upon a child file.
}


function walk_scope {
   declare -g NODE="$1"
   scope_${TYPEOF[$NODE]}
}


function scope_decl_section {
   # Save references: current SCOPE & NODE
   local -- scope_name=$SCOPE
   local -- node_name=$NODE
   local -n node=$NODE
   local -n scope=$SCOPE

   # Create symbol referring to this section.
   mk_symbol
   local -- symbol_name=$SYMBOL
   local -n symbol=$SYMBOL

   # Save reference to this declaration NODE in the symbol. Needed when merging
   # a child tree into the parent's. Any identifiers that are present in a
   # child's scope but not a parents are directly appended into the parent's
   # tree. The only way that's possible is with a reference to the node itself.
   symbol[node]=$node_name

   # Get string value of identifier node.
   local -- identifier_node=${node[name]}
   local -n identifier=$identifier_node
   local -- name="${identifier[value]}"

   # Add reference to current symbol in parent's SCOPE. First check if the user
   # has already defined a variable with the same name in this scope.
   if [[ ${scope[$name]} ]] ; then
      raise name_error "$name"
   else
      scope[$name]=$symbol_name
   fi

   # Create Type(kind: 'Section') for this node. Used in semantic analysis to
   # validate the config files.
   mk_type
   local -- type_name=$TYPE
   local -n type=$TYPE
   type[kind]='SECTION'
   symbol[type]=$type_name

   # Create new scope for children of this section. Populate parent's scope
   # with a reference to this one.
   mk_scope
   symbol[scope]=$SCOPE

   local -n items="${node[items]}" 
   for nname in "${items[@]}"; do
      walk_scope $nname
   done

   # Check if this section is `required'. If any of its children are required,
   # it must be present in a child file.
   local -n child_scope="${symbol[scope]}"
   for c_sym_name in "${child_scope[@]}" ; do
      local -n c_sym=$c_sym_name
      if [[ "${c_sym[required]}" ]] ; then
         symbol[required]='yes'
         break
      fi
   done

   # Restore saved refs to the parent SCOPE, and current NODE.
   declare -g NODE=$node_name
   declare -g SCOPE=$scope_name
}


function scope_decl_variable {
   # Save references: current SCOPE & NODE
   local -- scope_name=$SCOPE
   local -- node_name=$NODE
   local -n node=$NODE
   local -n scope=$SCOPE

   # Create symbol referring to this section.
   mk_symbol
   local -- symbol_name=$SYMBOL
   local -n symbol=$SYMBOL

   # Save reference to this declaration NODE in the symbol. Needed when merging
   # a child tree into the parent's. Any identifiers that are present in a
   # child's scope but not a parents are directly appended into the parent's
   # tree. The only way that's possible is with a reference to the node itself.
   symbol[node]=$node_name

   # Get string value of identifier node.
   local -- identifier_node=${node[name]}
   local -n identifier=$identifier_node
   local -- name="${identifier[value]}"

   # Add reference to current symbol in parent's SCOPE. First check if the user
   # has already defined a variable with the same name in this scope.
   if [[ ${scope[$name]} ]] ; then
      raise name_error "$name"
   else
      scope[$name]=$symbol_name
   fi

   if [[ ${node[type]} ]] ; then
      walk_scope ${node[type]}
      symbol[type]=$TYPE
   else
      # If user does not specify a type declaration, it gets an implicit ANY
      # type that matches anything.
      mk_type
      local -n type=$TYPE
      type[kind]='ANY'
      symbol[type]=$TYPE
   fi

   # Variables are `required' when they do not contain an expression. A child
   # must fill in the value.
   if [[ ! ${node[expr]} ]] ; then
      symbol[required]='yes'
   fi

   declare -g NODE=$node_name
}


function scope_typedef {
   local -- save=$NODE
   local -n node=$save

   walk_scope ${node[kind]}
   local -- tname=$TYPE

   if [[ ${node[subtype]} ]] ; then
      walk_scope ${node[subtype]}
      type[subtype]=$TYPE
   fi

   declare -g TYPE=$tname
   declare -g NODE=$save
}


# Identifiers in this context are used only as type names.
function scope_identifier {
   local -- nname=$NODE
   local -n node=$NODE

   local -- kind=${DEFAULT_TYPES[${node[value]}]}
   if [[ ! $kind ]] ; then
      raise invalid_type_error "${node[value]}"
   fi

   mk_type
   local -- tname=$TYPE
   local -n type=$TYPE
   type[kind]="$kind"
}

#───────────────────────────────( merge trees )─────────────────────────────────
# After generating the symbol tables for the parent & child, iterate over the
# parent's, merging in nodes. I'm not 100% sure if this should be in the
# compiler.
#
# Merging is only necessary if the parent has %constrain statements.

# Gives friendly means of reporting to the user where an error has occurred.
# As we descend into each scope, push its name to the stack. Print by doing a
# SCOPE_STR.join('.'). Example:
#
#> SCOPE_STR=([0]='global' [1]='subsection')
#> identifier=${node[name]}
#>
#> for s in "${SCOPE_STR[@]}" ; do
#>    echo -n "${s}."
#> done
#> echo "${identifier}"  # -> [$section.]+$identifier -> sect1.sect2.key
declare -a SCOPE_STR=()
declare -- FQ_NAME=

# Don't want to exit instantly on the first missing key. Collect them all,
# report and fail at the end.
declare -a MISSING_KEYS=()

# Currently just logs the `path' to the identifier whose type was incorrect.
# Need to also display file/line/column/expected type information. This is
# different from a semantic typecheck. We're checking that a parent node is a
# Section, and the child is as well. Or the parent is a variable declaration,
# and the child matches.
declare -a SYMBOL_MISMATCH=()

# Cannot re-declare a typedef that's already been defined.
declare -a TYPE_REDECLARE=()


function merge_scope {
   local -- parent_scope_root=$1
   local -n parent_scope=$1

   local -- child_scope_root=$2
   local -n child_scope=$2

   # We iterate over the parent scope. So we're guaranteed to hit every key
   # there. The child scope may contain *extra* keys that we need to merge in.
   # Every time we match a key from the parent->child, we can pop it from this
   # copy. Anything left is a duplicate that must be merged.
   local -A child_keys=( "${!child_scope[@]}" )
   for k in "${!child_scope[@]}" ; do
      child_keys[$k]=
   done
   
   for p_key in "${!parent_scope[@]}" ; do
      SCOPE_STR+=( "$p_key" )

      # Parent Symbol.
      local -- p_sym_name="${parent_scope[$p_key]}"
      local -n p_sym=$p_sym_name
      local -- p_node=${p_sym[node]}

      # For error reporting, build a "fully qualified" path to this node.
      local fq_name=''
      for s in "${SCOPE_STR[@]}" ; do
         fq_name+="${s}."
      done
      fq_name+="${p_key}"
      FQ_NAME="$fq_name"

      # Parent type information.
      local -- p_type_name="${p_sym[type]}"
      local -n p_type=$p_type_name

      # Child Symbol.
      local -- c_sym_name="${child_scope[$p_key]}"
      
      # Pop reference to child symbol from the `child_keys[]` copy. Will allow
      # us to check at the end if there are leftover keys that are defined in
      # the child, but not in the parent.
      unset child_keys[$p_key]

      if [[ "${p_type[kind]}" == 'SECTION' ]] ; then
         merge_section  "$p_sym_name" "$c_sym_name"
      else
         merge_variable "$p_sym_name" "$c_sym_name"
      fi

      SCOPE_STR=( "${SCOPE_STR[@]::${#SCOPE_STR[@]}-1}" )
   done

   # Any additional keys from the child need to be copied into both...
   #  1. the parent's .items[] array
   #  2. the parent's symbol table
   for c_key in "${child_keys[@]}" ; do
      # Add to symtab.
      parent_scope[$c_key]="${child_scope[$c_key]}" 

      local -n c_sym="${child_scope[$c_key]}"
      local -n section=$SECTION
      local -n items="${section[items]}"

      # Add to items.
      items+=( "${c_sym[node]}" )
   done
}


function merge_section {
   # It's easier to think about the conditions in which a merge *fails*. A
   # section merge fails when:
   #  1. It is required in the parent, and missing in the child
   #  2. It is of a non-Section type in the child

   local -- p_sym_name="$1"
   local -- c_sym_name="$2"

   # We know the parent symbol exists. Can safely nameref it.
   local -n p_sym="$p_sym_name"

   # case 1.
   # Child section is missing, but was required in the parent.
   if [[ ! "$c_sym_name" ]] ; then
      if [[ "${p_sym[required]}" ]] ; then
         MISSING_KEYS+=( "$FQ_NAME" )
         return 1
      fi

      # If child section was missing, but not required... nothing to do. We
      # gucci & scoochie.
      return 0
   fi

   local -n c_sym="$c_sym_name"
   local -n c_type="${c_sym[type]}"
   
   # case 2.
   # Found child node under the same identifier, but not a Section.
   if [[ ${c_type[kind]} != 'SECTION' ]] ; then
      SYMBOL_MISMATCH+=( "$FQ_NAME" )
      return 1
   fi

   SECTION="${p_sym[node]}"
   merge_scope "${p_sym[scope]}" "${c_sym[scope]}"
}


function merge_variable {
   # It's easier to think about the conditions in which a merge *fails*. A
   # variable merge fails when:
   #  1. If the child does not exist, and...
   #     a. the parent was required
   #  2. If the child exist, and...
   #     a. it's not also a type(var_decl)
   #     b. it's declaring a different type

   local -- p_sym_name="$1"
   local -- c_sym_name="$2"

   # We know the parent symbol exists. Can safely nameref it.
   local -n p_sym="$p_sym_name"

   # case 1a.
   if [[ ! "$c_sym_name" ]] ; then
      if [[ "${p_sym[required]}" ]] ; then
         MISSING_KEYS+=( "$FQ_NAME" )
         return 1
      fi
      return 0
   fi

   local -n c_sym="$c_sym_name"

   # case 2a.
   # Expecting a variable declaration, child is actually a Section.
   local -n c_type="${c_sym[type]}" 
   if [[ "${c_type[kind]}" == 'SECTION' ]] ; then
      SYMBOL_MISMATCH+=( "$FQ_NAME" )
      return 1
   fi

   # case 2b.
   # The type of the child must defer to the type of the parent.
   if ! merge_type "${p_sym[type]}" "${c_sym[type]}" ; then
      TYPE_REDECLARE+=( "$FQ_NAME" )
      return 1
   fi

   # If we haven't hit any errors, can safely copy over the child's value to the
   # parent.
   local -n p_node="${p_sym[node]}" 
   local -n c_node="${c_sym[node]}" 
   if [[ "${c_node[expr]}" ]] ; then
      p_node[expr]="${c_node[expr]}" 
   fi

   # TODO: feature
   # This is where we would also append the directive/test context information
   # over. But it doesn't exist yet.
}


function merge_type {
   # This it's not a semantic typecheck. It only enforces the deference in a
   # child's typedef. The child must either...
   #  1. match exactly
   #  2. be 'ANY'
   #  3. not exist (in the case of a parent subtype, and the child's is empty)

   # case 3.
   # If there's a defined parent type, but no child.
   [[ $1 && ! $2 ]] && return 0

   local -- t1_name="$1" t2_name="$2"
   local -n t1="$1"      t2="$2"

   # case 2.
   # Doesn't matter what the parent's type was. The child is not declaring it,
   # thus respecting the imposed type.
   [[ "${t2[kind]}" == 'ANY' ]] && return 0

   # case 1.
   # Parent and child's types match exactly.
   if [[ ${t1[kind]} == ${t2[kind]} ]] ; then
      return 0
   fi

   # Same as above, but for any subtypes.
   if [[ ${t1[subtype]} ]] ; then
      merge_type "${t1[subtype]}" "${t2[subtype]}"
      return $?
   fi

   return 1
}


#────────────────────────────────( build data )─────────────────────────────────
# TODO: documentation
declare -- KEY= DATA=
declare -i DATA_NUM=${TYPE_NUM:-0}

function mk_data_dict {
   (( DATA_NUM++ ))
   local   --  dname="_DATA_${DATA_NUM}"
   declare -gA $dname
   declare -g  DATA=$dname
   local   -n  data=$dname
   data=()
}


function mk_data_array {
   (( DATA_NUM++ ))
   local   --  dname="_DATA_${DATA_NUM}"
   declare -ga $dname
   declare -g  DATA=$dname
   local   -n  data=$dname
   data=()
}


function walk_data {
   declare -g NODE="$1"
   data_${TYPEOF[$NODE]}
}


function data_decl_section {
   # Save reference to current NODE. Restored at the end.
   local -- save=$NODE
   local -n node=$save

   # Create data dictionary object.
   mk_data_dict
   local -- dname=$DATA
   local -n data=$DATA

   walk_data ${node[name]}
   local -- key="$DATA"

   local -n items="${node[items]}" 
   for nname in "${items[@]}"; do
      walk_data $nname
      data[$KEY]="$DATA"
   done

   declare -g KEY="$key"
   declare -g DATA="$dname"
   declare -g NODE="$save"
}


function data_decl_variable {
   local -- save=$NODE
   local -n node=$save

   walk_data ${node[name]}
   local -- key="$DATA"

   if [[ -n ${node[expr]} ]] ; then
      walk_data ${node[expr]}
   else
      declare -g DATA=''
   fi

   declare -g KEY="$key"
   declare -g NODE=$save
}


function data_unary {
   local -- save=$NODE
   local -n node=$save

   # The only unary expression right now is negation.
   walk_data ${node[rhs]}
   local -i rhs=$DATA

   declare -g DATA=$(( -1 * $rhs ))
   declare -g NODE=$save
}


function data_array {
   local -- save=$NODE
   local -n node=$save

   mk_data_array
   local -- dname=$DATA
   local -n data=$DATA

   for nname in "${node[@]}"; do
      walk_data $nname
      data+=( "$DATA" )
   done

   declare -g DATA=$dname
   declare -g NODE=$save
}


function data_boolean {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
}


function data_integer {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
}


function data_string {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
}


function data_path {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
}


function data_identifier {
   local -n node=$NODE
   declare -g DATA="${node[value]}"
}


##─────────────────────────────( semantic analysis )─────────────────────────────
## Easy way of doing semantic analysis is actually similar to how we did the node
## traversal in the `conf()` function. Globally point to a Type() node.
## Everything at that level should match the Type.kind property. Descend into
## node, set global Type to previous Type.subtype (if exists). Continue semantic
## analysis.
# 
## Holds the intended target from a typedef. Compared to sub-expression's Types.
#declare -- TARGET_TYPE=



#function type_equality {
#   [[ "$1" ]] || return 1
#   local -- t1_name="$1"
#   local -n t1="$1"
#
#   [[ "$2" ]] || return 1
#   local -- t2_name="$2"
#   local -n t2="$2"
#
#   if [[ ${t1[kind]} != ${t2[kind]} ]] ; then
#      return 1
#   fi
#
#   if [[ ${t1[subtype]} ]] ; then
#      type_equality "${t1[subtype]}" "${t2[subtype]}" 
#      return $?
#   fi
#
#   return 0
#}


#
#function walk_semantics {
#   declare -g NODE="$1"
#   semantics_${TYPEOF[$NODE]}
#}
#
#
#function semantics_decl_section {
#   local -- save=$NODE
#   local -n node=$save
#
#   declare -n items="${node[items]}" 
#   for each in "${items[@]}"; do
#      walk_semantics $each
#   done
#
#   declare -g NODE=$save
#}
#
#
#function semantics_decl_variable {
#   local -- save=$NODE
#   local -n node=$save
#
#   # Type declarations cannot be nested. Thus this must be a "top level". Clear
#   # any previously set TARGET_TYPE, and start anew.
#   declare -g TARGET_TYPE=
#
#   # If there's no type declaration, or expression, there's nothing to do in
#   # this phase.
#   [[ -z ${node[type]} || -z ${node[expr]} ]] && return
#
#   walk_semantics ${node[type]}
#   local -n target=$TARGET_TYPE
#
#   walk_semantics ${node[expr]}
#   local -n expr_type=$TYPE
#
#   if [[ "${target[kind]}" != "${expr_type[kind]}" ]] ; then
#      #raise 'type_error' "${target[kind]}" "${expr_type[kind]}"
#      echo "Type Error. Wants(${target[kind]}), got(${expr_type[kind]})" 1>&2
#      exit -1
#   fi
#
#   declare -g NODE=$save
#}
#
#
#function semantics_typedef {
#   local -- save=$NODE
#   local -n node=$save
#
#   walk_semantics ${node[kind]}
#   local -- tname=$TYPE
#   local -n type=$TYPE
#
#   if [[ -n ${node[subtype]} ]] ; then
#      walk_semantics ${node[subtype]}
#      type[subtype]=$TYPE
#   fi
#
#   declare -g TARGET_TYPE=$tname
#   declare -g NODE=$save
#}
#
#
# This can only occur within a validation section. Validation expressions must
# return a boolean.
#function semantics_unary {
#   local -- save=$NODE
#   local -n node=$save
#
#   walk_semantics ${node[right]}
#
#   declare -g NODE=$save
#}
#
#
#function semantics_array {
#   local -- save=$NODE
#   local -n node=$save
#
#   # Save reference to the type that's expected of us.
#   local -- target_save=$TARGET_TYPE
#   local -n target=$TARGET_TYPE
#
#   # If we're not enforcing some constraints on the subtypes, then don't check
#   # them.
#   [[ -z ${target[subtype]} ]] && return
#
#   declare -g TARGET_TYPE=${target[subtype]}
#   local   -n subtype=${target[subtype]}
#
#   for nname in "${node[@]}"; do
#      walk_semantics $nname
#      local -n child=$TYPE
#
#      if [[ ${subtype[kind]} != ${child[kind]} ]] ; then
#         #raise 'type_error' "${subtype[kind]}" "${child[kind]}"
#         echo "Type Error. Wants(${subtype[kind]}), got(${child[kind]})" 1>&2
#         exit -1
#      fi
#   done
#
#   mk_type
#   local -n type=$TYPE
#   type[kind]='ARRAY'
#
#   declare -g TARGET_TYPE=$target_save
#   declare -g NODE=$save
#}
#
#
#function semantics_boolean {
#   mk_type
#   local -- tname=$TYPE
#   local -n type=$TYPE
#   type[kind]='BOOLEAN'
#}
#
#
#function semantics_integer {
#   mk_type
#   local -- tname=$TYPE
#   local -n type=$TYPE
#   type[kind]='INTEGER'
#}
#
#
#function semantics_string {
#   mk_type
#   local -- tname=$TYPE
#   local -n type=$TYPE
#   type[kind]='STRING'
#}
#
#
#function semantics_path {
#   mk_type
#   local -- tname=$TYPE
#   local -n type=$TYPE
#   type[kind]='PATH'
#}
#
#
#function semantics_identifier {
#   mk_type
#   local -- tname=$TYPE
#   local -n type=$TYPE
#
#   local -n node=$NODE
#   local -- kind=${BUILT_INS[${node[value]}]}
#   if [[ -z $kind ]] ; then
#      echo "Invalid type \`${node[value]}\`" 1>&2
#      exit -1
#   fi
#
#   type[kind]=$kind
#}
## pass.
## No semantics to be checked here. Identifiers can only occur as names to
## elements, or function calls.


#───────────────────────────────( pretty print )────────────────────────────────
# For debugging, having a pretty printer is super useful. Also supes good down
# the line when we want to make a function for script-writers to dump a base
# skeleton config for users.

declare -i INDENT_FACTOR=2
declare -i INDENTATION=0


function walk_pprint {
   declare -g NODE="$1"
   pprint_${TYPEOF[$NODE]}
}


function pprint_decl_section {
   # Save reference to current NODE. Restored at the end.
   local -- save=$NODE
   local -n node=$save

   walk_pprint ${node[name]}
   printf ' {\n'

   (( INDENTATION++ ))

   local -n items="${node[items]}" 
   for nname in "${items[@]}"; do
      walk_pprint $nname
   done

   (( INDENTATION-- ))
   printf "%$(( INDENTATION * INDENT_FACTOR ))s}\n" ''

   declare -g NODE="$save"
}


function pprint_decl_variable {
   local -- save=$NODE
   local -n node=$save

   printf "%$(( INDENTATION * INDENT_FACTOR ))s" ''
   walk_pprint ${node[name]}

   if [[ ${node[type]} ]] ; then
      printf ' ('
      walk_pprint "${node[type]}"
      printf ')'
   fi

   if [[ ${node[expr]} ]] ; then
      printf ' '
      walk_pprint ${node[expr]}
      printf ';\n'
   fi

   declare -g NODE=$save
}


function pprint_typedef {
   local -- save=$NODE
   local -n node=$save

   walk_pprint "${node[kind]}"

   if [[ "${node[subtype]}" ]] ; then
      printf ':'
      walk_pprint "${node[subtype]}"
   fi

   declare -g NODE=$save
}


function pprint_array {
   local -- save=$NODE
   local -n node=$save

   (( INDENTATION++ ))
   printf '['

   for nname in "${node[@]}"; do
      printf "\n%$(( INDENTATION * INDENT_FACTOR ))s" ''
      walk_pprint $nname
   done

   (( INDENTATION-- ))
   printf "\n%$(( INDENTATION * INDENT_FACTOR ))s]" ''

   declare -g NODE=$save
}


function pprint_boolean {
   local -n node=$NODE
   printf '%s' "${node[value]}"
}


function pprint_integer {
   local -n node=$NODE
   printf '%s' "${node[value]}"
}


function pprint_string {
   local -n node=$NODE
   printf '"%s"' "${node[value]}"
}


function pprint_path {
   local -n node=$NODE
   printf "'%s'" "${node[value]}"
}


function pprint_identifier {
   local -n node=$NODE
   printf '%s' "${node[value]}"
}
