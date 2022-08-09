#!/bin/bash
#
# Requires from ENV:
#  list:path   FILES[]

function init_scanner {
   : 'Some variables need to be reset at the start of every run. They hold
      information that should not be carried from file to file.'

   # Reset global vars prior to each run.
   (( FILE_IDX = ${#FILES[@]} - 1 )) ||:

   # Fail if no file.
   if [[ "${#FILES[@]}" -eq 0 ]] ; then
      raise no_input
   fi

   # File & character information.
   declare -ga  CHARRAY=()
   #declare -ga  FILE_LINES=()
   # TODO: error reporting
   # Currently 

   # Token information.
   declare -ga  TOKENS=()
   declare -gi  TOKEN_NUM=0

   declare -gA  FREEZE CURSOR=(
      [offset]=-1
      [lineno]=1
      [colno]=0
   )
}


function Token {
   : "Effectively a Class. Creates instances of Token with information for
      the position in the file, as well as the character type/value."

   local type=$1  value=$2

   # Realistically we can just do "TOKEN_$(( ${#TOKEN_NUM[@]} + 1 ))". Feel like
   # that add visual complexity here, despite removing slight complexity of yet
   # another global variable.
   local tname="TOKEN_${TOKEN_NUM}"
   declare -gA "${tname}"

   # Nameref to newly created global token.
   declare -n t="$tname"

   # Token data.
   t['type']="$type"
   t['value']="$value"

   # Cursor information (position in file & line).
   t['offset']=${FREEZE[offset]}
   t['lineno']=${FREEZE[lineno]}
   t['colno']=${FREEZE[colno]}

   # shellcheck disable=SC2034
   # ^-- doesn't know this is used later.
   t['file']="${FILE_IDX}"

   TOKENS+=( "$tname" )
   (( TOKEN_NUM++ )) ||:
}

                                     
#══════════════════════════════════╡ SCANNER ╞══════════════════════════════════
declare -A KEYWORD=(
   ['true']=true
   ['false']=true
   ['and']=true
   ['or']=true
   ['not']=true
   ['include']=true
   ['constrain']=true
)


declare -g  CURRENT PEEK
declare -ga CHARRAY=()      # Array of each character in the file.

function l_advance {
   # Advance cursor position, pointing to each sequential character. Also incr.
   # the column number indicator. If we go to a new line, it's reset to 0.
   #
   # NOTE: So this has some of the silliest garbage of all time. In bash, using
   # ((...)) for arithmetic has a non-0 return status if the result is 0. E.g.,
   #> (( 1 )) ; echo $?    #  0
   #> (( 2 )) ; echo $?    #  0
   #> (( 0 )) ; echo $?    #  1
   # So the stupid way around this... add an `or true`. This is the short form:
   (( ++CURSOR['offset'] )) ||:
   (( ++CURSOR['colno']  ))

   # This is a real dumb use of bash's confusing array indexing.
   CURRENT=${CHARRAY[CURSOR['offset']]}
   PEEK=${CHARRAY[CURSOR['offset']+1]}

   if [[ $CURRENT == $'\n' ]] ; then
      ((CURSOR['lineno']++))
      CURSOR['colno']=0
   fi
}


function scan {
   # Creating secondary line buffer to do better debug output printing. It would
   # be more efficient to *only* hold a buffer of lines up until each newline.
   # Unpon an error, we'd only need to save the singular line, then can resume
   #mapfile -td $'\n' FILE_LINES < "${FILES[-1]}"
   # TODO: error reporting
   # Will need a separate array for each file. Probably have a second array
   # parallel to FILES[]. The index of the FILE will match the name of the
   # array holding the lines.

   # For easier lookahead, read all characters first into an array. Allows us
   # to seek/index very easily.
   while read -rN1 character ; do
      CHARRAY+=( "$character" )
   done < "${FILES[-1]}"

   while [[ ${CURSOR[offset]} -lt ${#CHARRAY[@]} ]] ; do
      l_advance ; [[ -z "$CURRENT" ]] && break

      # Save current cursor information.
      FREEZE['offset']=${CURSOR['offset']}
      FREEZE['lineno']=${CURSOR['lineno']}
      FREEZE['colno']=${CURSOR['colno']}

      # Skip comments.
      if [[ $CURRENT == '#' ]] ; then
         l_comment ; continue
      fi

      # Skip whitespace.
      if [[ $CURRENT =~ [[:space:]] ]] ; then
         continue
      fi

      # Symbols.
      case $CURRENT in
         ';')  Token       'SEMI' "$CURRENT"  ; continue ;;
         ':')  Token      'COLON' "$CURRENT"  ; continue ;;
         '-')  Token      'MINUS' "$CURRENT"  ; continue ;;
         '$')  Token     'DOLLAR' "$CURRENT"  ; continue ;;
         '%')  Token    'PERCENT' "$CURRENT"  ; continue ;;
         '?')  Token   'QUESTION' "$CURRENT"  ; continue ;;

         '(')  Token    'L_PAREN' "$CURRENT"  ; continue ;;
         ')')  Token    'R_PAREN' "$CURRENT"  ; continue ;;

         '[')  Token  'L_BRACKET' "$CURRENT"  ; continue ;;
         ']')  Token  'R_BRACKET' "$CURRENT"  ; continue ;;

         '{')  Token    'L_BRACE' "$CURRENT"  ; continue ;;
         '}')  Token    'R_BRACE' "$CURRENT"  ; continue ;;
      esac

      # Identifiers.
      if [[ $CURRENT =~ [[:alpha:]_] ]] ; then
         l_identifier ; continue
      fi

      # Strings. Surrounded by `"`.
      if [[ $CURRENT == '"' ]] ; then
         l_string ; continue
      fi

      # Paths. Surrounded by `'`.
      if [[ $CURRENT == "'" ]] ; then
         l_path ; continue
      fi

      # Numbers.
      if [[ $CURRENT =~ [[:digit:]] ]] ; then
         # Bash only natively handles integers. It's not able to do floats
         # without bringing `bc` or something. For now, that's all we'll also
        # support. Maybe later I'll add a float type, just so I can write some
         # external functions that support float comparisons.
         l_number ; continue
      fi

      # Can do a dedicated error pass, scanning for error tokens, and assembling
      # the context to print useful debug messages.
      Token 'ERROR' "$CURRENT"
   done

   Token 'EOF'
}


function l_comment {
   # There are no multiline comments. Seeks from '#' to the end of the line.
   while [[ -n $CURRENT ]] ; do
      [[ "$PEEK" =~ $'\n' ]] && break
      l_advance
   done
}


function l_identifier {
   local buffer="$CURRENT"

   while [[ -n $CURRENT ]] ; do
      [[ $PEEK =~ [^[:alnum:]_] ]] && break
      l_advance ; buffer+="$CURRENT"
   done

   if [[ -n ${KEYWORD[$buffer]} ]] ; then
      Token "${buffer^^}" "$buffer"
   else
      Token 'IDENTIFIER' "$buffer"
   fi
}


function l_string {
   local -a buffer=()

   while [[ -n $CURRENT ]] ; do
      if [[ $PEEK == '"' ]] ; then
         # shellcheck disable=SC1003
         # Misidentified error.
         if [[ $CURRENT == '\' ]] ; then
            # shellcheck disable=SC2184
            unset buffer[-1]
         else
            break
         fi
      fi
      l_advance ; buffer+=( "$CURRENT" )
   done

   local join=''
   for c in "${buffer[@]}" ; do
      join+="$c"
   done

   # Create token.
   Token 'STRING' "$join"

   # Skip final closing `'`.
   l_advance
}


function l_path {
   local -a buffer=()

   while [[ -n $CURRENT ]] ; do
      if [[ $PEEK == "'" ]] ; then
         # shellcheck disable=SC1003
         # Misidentified error.
         if [[ $CURRENT == '\' ]] ; then
            # shellcheck disable=SC2184
            unset buffer[-1]
         else
            break
         fi
      fi
      l_advance ; buffer+=( "$CURRENT" )
   done

   local join=''
   for c in "${buffer[@]}" ; do
      join+="$c"
   done

   # Create token.
   Token 'PATH' "$join"

   # Skip final closing `'`.
   l_advance
}


function l_number {
   local number="${CURRENT}"

   while [[ $PEEK =~ [[:digit:]] ]] ; do
      l_advance ; number+="$CURRENT"
   done

   Token 'INTEGER' "$number"
}
