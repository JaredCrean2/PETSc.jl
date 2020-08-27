module PETSc

using MPI, LinearAlgebra, SparseArrays

using PETSc_jll

include("const.jl")
include("lib.jl")
include("init.jl")
#include("viewer.jl")
include("vec.jl")
include("mat.jl")
include("ksp.jl")

end
