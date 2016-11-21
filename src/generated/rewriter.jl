# rewrites the expressions generated by clang

using DataStructures

# node: the input obuff has the type annotations in the function signature and the types in the ccall as references to the same Expr object.  A deepcopy and overwrite is needed to fix hthis

# dictionary to map pointer types to desired type
# isdefined(modulename, :name) -> Bool
# use wrap_contex.commonbuf for dictionary of names that have been defined

############################################################################### Only these parameters need to be modified for the different
# version of PETSc

# used to modify function signatures
type_dict = Dict{Any, Any} (
  :PetscScalar => :Float32,
  :PetscReal => :Float32,
  :PetscInt => :Int64,
)

const petsc_libname = :petscRealSingle

##############################################################################


val_tmp = type_dict[:PetscScalar]
type_dict_single = Dict{Any, Any} (
:(Ptr{UInt8}) => Union{Cstring, String, Symbol, Array{UInt8}, Ptr{UInt8}}
)


# used to convert typealiases to immutable type definionts
# currently, if the key exists, it is converted
# if value == 1, create new immutable type
# otherwise replace key with value
# also used for function signatures
new_type_dict = Dict{Any, Any} (
  :Vec => :(Vec{$val_tmp}),
  :Mat => :(Mat{$val_tmp}),
  :KSP => :(KSP{$val_tmp}),
  :PC => :(PC{$val_tmp}),
  :PetscViewer => :(PetscViewer{$val_tmp}),
  :PetscOption => :(PetscOption{$val_tmp}),
  :IS => :(IS{$val_tmp}),
  :ISLocalToGlobalMapping => :(ISLocalToGlobalMapping{$val_tmp}),
  :ISColoring => :(ISColoring{$val_tmp}),
  :PetscLayout => :(PetscLayout{$val_tmp}),
  :VecScatter => :(VecScatter{$val_tmp}),
  :AO => :(AO{$val_tmp}),
  :TS => :(TS{$val_tmp})
)

# definitions that will be provided, but don't come from Petsc
# mostly MPI stuff
const_defs = Dict{Any, Any} (
  :MPI_COMM_SELF => 1,
  :MPI_Comm => 1,
  :comm_type => 1,
)

# dictionary to hold names of types
# that are aliased to Symbol
Symbol_type_dict = Dict{Any, Any} ()

# create a string array mirroring a Symbol array
function send_Symbol(x::AbstractArray)
  string_arr = similar(x, ASCIIString)
  for i=1:length(x)
    if isdefined(x[i])
      string_arr[i] = copy(x[i])
    end
  end
  return string_arr
end

# get a string array and turn it into a Symbol array
function return_Symbol(string_array::AbstractArray, x::AbstractArray)
  for i=1:length(x)
    x[i] = string(string_array[i])
  end
end

# things to be recursively replaced in function signatures
sig_rec_dict = Dict{Any, Any} ()

for i in keys(type_dict)
  get!(sig_rec_dict, i, type_dict[i])
end

for i in keys(new_type_dict)
  get!(sig_rec_dict, i, new_type_dict[i])
end

# things to be replaced in function signatures only if they
# are top level (ie. this does a non recursive replace)
sig_single_dict = Dict{Any, Any} (
  :(Ptr{UInt8}) => :(Union{String, Cstring, Symbol, Array{UInt8}, Ptr{UInt8}}),
  :Int32 => :Integer,
  :Int64 => :Integer,
  :Cint => :Integer,
  :PetscInt => :Integer,
)

# list of Symbols to search for
# if none are found, then a dummy argument is added
sig_dummyarg_dict = Dict{Any, Any}(
  :PetscScalar => 1,
)

# add keys from new_type_dict because dummy arg check
# is done after type replacement
for i in values(new_type_dict)
  get!(sig_dummyarg_dict, i, 1)
end

# things to be recursively replaced in the ccall argument list
ccall_rec_dict = Dict{Any, Any} (
:MPI_Comm => :comm_type
)

for i in keys(type_dict)
  get!(ccall_rec_dict, i, type_dict[i])
end

for i in keys(new_type_dict)
  get!(ccall_rec_dict, i, new_type_dict[i])
end

# things to be replace in the ccall argument list only if
# they are top level (ie. this does a non recursive replace)
ccall_single_dict = Dict{Any, Any} (
  :(Ptr{UInt8}) => :Cstring,
)

# things to be replaced recurisvely in typealias rhs
typealias_rec_dict = Dict{Any, Any} ()

for i in keys(type_dict)
  get!(typealias_rec_dict, i, type_dict[i])
end

for i in keys(new_type_dict)
  get!(typealias_rec_dict, i, new_type_dict[i])
end

# dictionary of typealiases to exclude based on the lhs argument
typealias_lhs_dict = Dict{Any, Any} ()

for i in keys(type_dict)
  get!(typealias_lhs_dict, i, i)
end

# things to be replaced in typealias rhs, non recursive
# this creates a potential loophole for string handling
# because a Ptr{typealias} == Ptr{Ptr{UInt8}} will be
# handled incorrectly
typealias_single_dict = Dict{Any, Any} (
:(Ptr{UInt8}) => :Symbol
)

# key = typealias rhs values to exclude
# if values == 1, then create an immutable type
typealias_exclude_dict = Dict{Any, Any} (
)

for i in keys(new_type_dict)
  get!(typealias_exclude_dict, i, 1)
end

# things to be recurisvely replace in constant declaration rhs
const_rec_dict = Dict{Any, Any} (
:NULL => :C_NULL
)

for i in keys(type_dict)
  get!(const_rec_dict, i, type_dict[i])
end

for i in keys(new_type_dict)
  get!(const_rec_dict, i, new_type_dict[i])
end


#################################################################################

function petsc_rewriter(obuf)
  for i=1:length(obuf)
    ex_i = obuf[i]  # obuf is an array of expressions
    println("rewriting expression ", ex_i)

    if typeof(ex_i) == Expr
      head_i = ex_i.head  # function
      # each ex_i has 2 args, a function signature and a function body

      # figure out what kind of expression it is, do the right modification
      if head_i == :function  # function declaration
        obuf[i] = process_func(ex_i)
      elseif ex_i.head == :const  # constant declaration
        obuf[i] = process_const(ex_i)
      elseif ex_i.head == :typealias  # typealias definition
        obuf[i] = fix_typealias(ex_i)
      elseif ex_i.head == :type
        obuf[i] = process_type(ex_i)

      else  # some other kind of expression
        println("not processing expression", ex_i)

        # convert to concrete types
        for j in keys(type_dict)
          obuf[i] = replace_Symbol(ex_i, j, type_dict[j])
        end

        # purge anything unknown
        # this will always omit the expression because a newly declared name
        # will be unknown
        tmp = are_syms_defined(ex_i)
        if tmp != 0
          obuf[i] = "#= skipping undefined expression $ex_i =#"
        end

        # for types at least, arg[2] is the type name
        obj_name = ex_i.args[2]
        if haskey(wc.common_buf, obj_name)
          delete!(wc.common_buf, obj_name)
        end

      end

    elseif typeof(ex_i) == ASCIIString
      obuf[i] = process_string(ex_i)
    else
      println("not processing ", typeof(ex_i))
    end  # end if Expr

    println("final expression = ", obuf[i])
  end

  return obuf  # return modified obuf
end


##### functions to rewrite function signature #####
function process_func(ex)
  @assert ex.head == :function  # this is a function declaration

  println("at beginning of process_func, processing function ", ex.args[1])
  println("with body ", ex.args[2])



  ex.args[1] = rewrite_sig(ex.args[1])  # function signature

  println("after rewrite_sig, processing function ", ex.args[1])
  println("with body ", ex.args[2])

  ex.args[2] = rewrite_body(ex.args[2])  # function body

  println("processing function ", ex.args[1])
  println("with body ", ex.args[2])
  # now check if any undefined type annotations remain
  sum = 0
  ex_sig = ex.args[1]
  ex_body = ex.args[2]

  for i=2:length(ex_sig.args)  # loop over all arguments to the function
    # get the type annotation Expr or Symbol of argument i-1
    ex_sig_i = ex_sig.args[i].args[2]
    sum += are_syms_defined(ex_sig_i)
  end

  # now check ccall argument types
  ex_ccall = ex_body.args[1]
  ex_ccall_types = ex_ccall.args[3]  # the tuple of argument types
  sum += are_syms_defined(ex_ccall_types)

  if sum != 0
    return "#= skipping function with undefined Symbols: \n $ex \n=#"
  end

  # now add any extra expression needed
  ex = add_body(ex)
  return ex
end

# add any needed expressions to the body of the function
# this is post rewrite_sig, rewrite_body
function add_body(ex)

  ex_sig = ex.args[1]
  ex_body = ex.args[2]

  fname = ex_sig.args[1]
  @assert typeof(fname) == Symbol
  fname_str = string(fname)
  # check if a type annotation == Union(Ptr{Symbol_type}...)
  println("checking function ", fname_str, " for Symbols-string conversions")

  # check number of ccall args vs. function signature args
  numargs_ccall = length(ex_body.args[1].args) - 3
  numargs_func = length(ex_sig.args) - 1
  offset = numargs_func - numargs_ccall  # skip any function args in excess of ccall args

  for i in keys(Symbol_type_dict)
    for j=(2 + offset):length(ex_sig.args)  # loop over arguments to function
#      println("j = ", j)
      type_annot_j = ex_sig.args[j].args[2]  # get the teyp annotation
      argname_j = ex_sig.args[j].args[1]
      # check for arrays of Symbols that need to be copied into a string array
      if type_annot_j == :(Union{Ptr{$i}, StridedArray{$i}, Ptr{$i}, Ref{$i}})
        if contains(fname_str, "Get")  # array is to be populated
          # add calls to function body
          resize!(ex_body.args, length(ex_body.args) + 2)
          for i=2:(length(ex_body.args) - 1)
            ex_body.args[i] = deepcopy(ex_body.args[i-1])  # shift ccall to 2nd arg
          end
          ex_body.args[1] = nothing
          ex_body.args[end] = nothing

          # figure out where the ccall is
          ccall_index = get_ccall_index(ex_body)

          # construct the before function call
          call_ex =  Expr(:call, :Symbol_get_before, argname_j)
          new_argname = Symbol(string( argname_j, "_"))  # add underscore
          ex_body.args[1] = Expr(:(=), :($new_argname, tmp), deepcopy(call_ex))

          # construct the after call
          ex_body.args[length(ex_body.args)] = Expr(:call, :Symbol_get_after, new_argname, argname_j)

          # modify the ccall argument name
          println("ccall_index = ", ccall_index)
          ccall_ex = ex_body.args[ccall_index]

          @assert ccall_ex.head == :ccall
          ccall_ex.args[j + 3 - 1 - offset] = new_argname


        elseif contains(fname_str, "Set")  # array is already populated
          # add calls to function body
          resize!(ex_body.args, length(ex_body.args) + 1)
          for i=2:(length(ex_body.args))
            ex_body.args[i] = deepcopy(ex_body.args[i-1])  # shift ccall to 2nd arg
          end
          ex_body.args[1] = nothing

          # figure out where the ccall is
          ccall_index = get_ccall_index(ex_body)

          # construct the before function call
          call_ex =  Expr(:call, :Symbol_set_before, argname_j)
          new_argname = Symbol(string( argname_j, "_"))  # add underscore
          ex_body.args[1] = Expr(:(=), new_argname, deepcopy(call_ex))


          # modify the ccall argument name
          ccall_ex = ex_body.args[ccall_index]
          @assert ccall_ex.head == :ccall
          ccall_ex.args[j + 3 - 1 - offset] = new_argname


        else
          println(STDERR, "Warning, Symbol type conversion not handled in function ", fname_str)

        end  # end if contains(get)
      end  # end if type_annot_j == ...
    end  # end for j
  end # end loop over Symbol_type_dict



  # assign ccall error code to a variable, then return the variable
  # this should be the last modification made, because get_ccall_index
  # won't work after this
  ccall_index = get_ccall_index(ex_body)
  ccall_ex = deepcopy(ex_body.args[ccall_index])
  ex_body.args[ccall_index] = :(err = $ccall_ex)
  resize!(ex_body.args, length(ex_body.args) + 1)
  ex_body.args[end] = :(return err)


  # convert array of Symbols to array of strings
  # check signature for
  return deepcopy(ex)
end


function get_ccall_index(ex)
  # returns the index of the first ccall in the arguments of ex

  index = 0

  for i=1:length(ex.args)
    if typeof(ex.args[i]) == Expr
      if ex.args[i].head  == :ccall
        index = i
        break
      end
    end
  end

  if index == 0
    println("Warning, ccall not found")
  end

  return index
end


function rewrite_sig(ex)  # rewrite the function signature

  @assert ex.head == :call  # verify this is a function signature expression

  # ex.args[1] = function name, as a Symbol

  # check if function contains a PetscScalar

  # if yes, add paramterization, do search and replace PetscScalar -> S
  # also add macro

  println("rewrite_sig ex = ", ex)

  # Process all arguments of the function
  # Replace all pointers with Unions(Ptr, AbstractArray...)
  # do any other transformations in ptr_dict
  for i=2:length(ex.args)
    # each of ex.args is an expression containing arg name, argtype
    println("typeof(ex.args[$i]) = ", typeof(ex.args[i]))
    @assert typeof(ex.args[i]) == Expr  || typeof(ex.args[i]) == Symbol  # verify these are all expressions
    ex.args[i] = process_sig_arg(ex.args[i])  # process each expression
  end



  # check for any Symbol that will uniquely identify which
  # version of petsc to call
  println("checking for uniqueness of signature")
  println("ex = ", ex)

  val = contains_Symbol(ex, :PetscScalar)
  for i in keys(sig_dummyarg_dict)
    val += contains_Symbol(ex, i)
  end

  println("contains_Symbol = ", val)

  if val == 0  # if no arguments will make the function signature unique

    println("adding dummy arg")
    ex = add_dummy_arg(ex)
  end

  #=
  println("replacing typealiases")
  println("ex = ", ex)
  # do second pass to replace Petsc typealiases with a specific type
  for i=2:length(ex.args)
  for j in keys(type_dict)  # check for all types

  println("replacing ", j, ", with ", type_dict[j])
  ex.args[i] = replace_Symbol(ex.args[i], j, type_dict[j])
end
end

println("after modification rewrite_sig ex = ", ex)
=#
return ex
end

function process_sig_arg(ex)
  # take the expression that is an argument to the function and rewrite it

  @assert ex.head == :(::)

  # modify args here
  #   arg_name = ex.args[1]  # Symbol
  #   arg_type = ex.args[2]  # Expr contianing type tag
  println("ex.args[2] = ", ex.args[2])
  println("type = ", typeof(ex.args[2]))

  #   if typeof(ex.args[1]) == Symbol

  # get only typetag expression, modify it
  ex.args[2] = modify_typetag(ex.args[2])

  return ex
end

function modify_typetag(ex)
  # do non recursive replace first
  ex = deepcopy(get(sig_single_dict, ex, ex))

  # now do recursive search and replace
  for i in keys(sig_rec_dict)
    ex = deepcopy(replace_Symbol(ex, i, sig_rec_dict[i]))
  end

  # should make sure there are no nested pointers?
  #  @assert ex.head == :curly || ex.head == :Symbol # verify this is a typetag
  if typeof(ex) == Expr
    # replace pointer with Union of ptr, array, c_null
    if ex.head == :curly && ex.args[1] == :Ptr
      ptr_type = deepcopy(ex.args[2])
      ex =  :(Union{Ptr{$ptr_type}, StridedArray{$ptr_type}, Ptr{$ptr_type}, Ref{$ptr_type}})
    end
  end

  return ex
end

function add_param(ex)
  # add the {S <: PetscScalar} to a function declaration
  @assert typeof(ex) == Symbol  # make sure we don't already have a paramaterization

  # could do more extensive operations here
  return :($ex{S <: PetscScalars})
end

function add_dummy_arg(ex)
  # add a dummy argument to the function argument list
  # ex is the function name + args (ie. the entire function signature)

  println("adding dummy argument to ", ex)
  @assert ex.head == :call
  len = length(ex.args)
  resize!(ex.args, len + 1)


  println("length(ex.args) = ", length(ex.args))
  println("ex.args = ", ex.args)
  # shift  args up by one
  # first arg is function name, so don't modify it

  if length(ex.args) >= 3 # if there are any args to shift
    println("shifting arguments, length(ex.args) = ", length(ex.args))
    for i=length(ex.args):(-1):3
      ex.args[i] = ex.args[i-1]
      println("ex.args[$i] = ", ex.args[i])
    end
  end

  # insert dummy argument into first position
  # the PetscScalar will get rewritten to
  # appropriate type later
  val = type_dict[:PetscScalar]
  ex.args[2] = :(arg0::Type{$val})

  println("finished adding dummy arg, ex = ", ex)

  return ex
end

#####  function to  rewrite the body of the function #####
function rewrite_body(ex)  # rewrite body of a function
  @assert ex.head == :block
  # ex has only one argument, the ccall
  # could insert other statements arond the ccall here?
  ex.args[1] = process_ccall(ex.args[1])
  return ex
end


function process_ccall(ex)
  @assert ex.head == :ccall  # verify this is the ccall statement
  # args[1] = Expr, tuple of fname, libname
  # args[2] = return type, Symbol
  # args[3] = Expr, tuple of types to ccall
  # args[4] = Symbol, first argument name,
  # ...
  println("processing ccall ", ex)
  ex.args[1] = modify_libname(ex.args[1])  # change the library name
  ex.args[2] = modify_rettype(ex.args[2]) # change return type
  ex.args[3] = modify_types(ex.args[3])
  println("changing argument names")
  ex3 = ex.args[3]  # get expression of argument types
  #  ex4 = ex.args[4]  # get expression argument names

  @assert ex3.head == :tuple

  return ex
end

function modify_rettype(ex)

  println("modifying return type")
  println("ex = ", ex)
  return deepcopy(ex)
end

function modify_types(ex)
  @assert ex.head == :tuple

  # do non recursive replace first
  for i=1:length(ex.args)
    println("checking if ", ex.args[i], " has entry in ccall_single_dict")
    println("ex.args[$i] before = ", ex.args[i])
    ex.args[i] = get(ccall_single_dict, ex.args[i], ex.args[i])
    println("  after = ", ex.args[i])
  end

  println("  after all non-recursive replacements = ", ex.args)

  println("  ccall_rec_dict = ", ccall_rec_dict)
  # do recursive replacement
  for i in keys(ccall_rec_dict)
    for j=1:length(ex.args)
      ex.args[j] = replace_Symbol(ex.args[j], i, ccall_rec_dict[i])
    end
  end

  println("  after recursive replacement = ", ex.args)

  return deepcopy(ex)
end

function modify_libname(ex)
  @assert ex.head == :tuple
  ex.args[2] = petsc_libname  # replace libname with a new one
  return ex
end

##### functions to make consts into global consts #####

function process_const(ex)
  @assert ex.head == :const

  # do any replacements
  for j in keys(const_rec_dict)
    replace_Symbol(ex, j, const_rec_dict[j])
  end

  ex2 = ex.args[1]  # get the assignment

  rhs = ex2.args[2]
  tmp = are_syms_defined(rhs)
  if tmp != 0  # something is undefined
    lhs = ex2.args[1]
    delete!(wc.common_buf, lhs)  # remove lh from list of defined Symbols
    return "#skipping undefined $ex"  # replace expression with constant
  end

  # turn strings into Symbols
  if typeof(rhs) <: AbstractString
    ex2.args[2] = :(Symbol($rhs))
  end

  return deepcopy(ex)
end


function fix_typealias(ex)
  @assert ex.head == :typealias
  new_type = ex.args[1]

  println("fixing typealias ", ex)

  if haskey(typealias_exclude_dict, new_type)
    if typealias_exclude_dict[new_type] == 1
      # construct immutable type definition
      fields = Expr(:(::), :pobj, :(Ptr{Void}))
      body = Expr(:block, fields)
      typename = Expr(:curly, new_type, :T)  # add static parameter T
      ex_new = Expr(:type, false, typename, body)
      return ex_new
    else
      if haskey(wc.common_buf, new_type)
        delete!(wc.common_buf, new_type)  # record that Symbol is now undefined
      end
      return "# excluding $ex"
    end
  end

  # if we didn't create immutable type, transform the rhs according to the
  # dictionaries
  lhs = deepcopy(ex.args[1])
  rhs = deepcopy(ex.args[2])

  # check lhs for exclusion criteria
  if haskey(typealias_lhs_dict, lhs)
    # record that Symbol is now undefined
    delete!(wc.common_buf, lhs)
    return "# excluding lhs of  $ex"
  end

  # do non recursive replacement
  rhs = get(typealias_single_dict, rhs, rhs)

  if rhs == :Symbol
    get!(ccall_rec_dict, lhs, :(Ptr{UInt8}))  # make the ccall argument a UInt8 recursive
    get!(ccall_single_dict, lhs, :Cstring)  # make it a cstring for single level replacement
    get!(Symbol_type_dict, lhs, 1)  # record that this type is a Symbol
  end

  # do recursive replacement
  for i in keys(typealias_rec_dict)
    rhs = replace_Symbol(rhs, i, typealias_rec_dict[i])
  end

  # check for undefined Symbols

  tmp = are_syms_defined(rhs)
  if tmp != 0
    delete!(wc.common_buf, lhs)  # record that the lhs Symbol is now undefined
    return "# skipping undefined typealias $ex"
  end

  # if no conditions met
  # construct a new typealias

  return :(typealias $lhs $rhs)
end

# string processing
function process_string(ex)
  return "#= $ex =#"
end

##### Type declaration functions #####
function process_type(ex)

  println("processing type declaration ", ex)

  # make all types (structs) immutable
  ex.args[1] = false

  ex_body = ex.args[3]  # body of type declaration

  # check that every type annotation is fully defined
  for i=1:length(ex_body.args)
    # if this is a type annotation expression
    if typeof(ex_body.args[i]) == Expr && ex_body.args[i].head == :(::)
      type_sym = ex_body.args[i].args[2]
      tmp = are_syms_defined(type_sym)
      if tmp != 0
        new_name = ex.args[2]  # get the name of the type being declared
        delete!(wc.common_buf, new_name)

        return "#= skipping type declaration with undefined Symbols:\n$ex \n=#"
      end
    end
  end

  return ex
end

##### Misc. functions ####
function contains_Symbol(ex, sym)
  # recursively check Symbol in expression ex to see if sym is present
  sum = 0
  if ex == sym
    return 1
  elseif typeof(ex) == Expr
    #check the arguments of the exprssion
    for i=1:length(ex.args)
      sum += contains_Symbol(ex.args[i], sym)
    end
  else  # something unknown
    return 0  # assuming we did not find the Symbol
  end

  return sum
end

function check_annot(ex, sym::Symbol)
  # check a type annotation
  for i=1:length(ex.args)
    if ex.args[i] == sym
      return true
    end
  end
  return false
end

function replace_Symbol(ex, sym_old, sym_new)
  if ex == sym_old
    return deepcopy(sym_new)
  elseif typeof(ex) == Expr  # recurse the arguments
    for i=1:length(ex.args)
      ex.args[i] = replace_Symbol(ex.args[i], sym_old,sym_new)
    end
  else  # don't know/care what this is
    return deepcopy(ex)
  end

  return deepcopy(ex)
end

function count_depth(seed::Integer, ex)
  # primitive attempt to count number of nodes on tree
  if typeof(ex) == Expr
    for i=1:length(ex.args)

      seed += count_depth(seed, ex.args[i])
    end
  else
    println("ex = ", ex, " returning 1")
    return 1
  end
  return seed
end

function are_syms_defined(ex)
  # check all Symbols, see if they are defined by julia or by
  # the wrap contex
  undefined_syms = 0  # approximate counter of undefined Symbols found

  if typeof(ex)  == Expr  # keep recursing
    for i=1:length(ex.args)
      undefined_syms +=  are_syms_defined(ex.args[i])
    end  # end loop over args
  elseif typeof(ex) == Symbol  # if this is a Symbol
    if isdefined(ex) || haskey(wc.common_buf, ex) || haskey(const_defs, ex)
      return 0  # Symbol is defined
    else
      return 1
    end
  else # we don't know/care what this expression is
    println("  not counting unknown expression ", ex)
    return undefined_syms
  end  # end if ... elseifa

  return undefined_syms
end
