# This implements src/snes/examples/tutorials/ex2.c from PETSc using the PETSc.jl package, using SNES
#
# This solves the equations sequentially
# 
# Newton method to solve u'' + u^{2} = f, sequentially.

using PETSc, MPI, LinearAlgebra, SparseArrays, UnicodePlots

if ~MPI.Initialized()
    MPI.Init()
end

petsclib = PETSc.petsclibs[1]
PETSc.initialize(petsclib)

"""    
    Computes initial guess 
"""
function FormInitialGuess!(x)
    for i=1:length(x)
        x[i] = 0.50;
    end
end

""" 
    Computes rhs forcing function 
""" 
function SetInitialArrays(n)
    h =  1.0/(n-1.0)
    F = zeros(n);
    xp = 0.0;
    for i=1:n 
        v    = 6.0*xp + (xp+1.e-12)^6.0; 
        F[i] = v;
        xp   = xp+h;
    end

    return F
end

"""
    Computes the residual f, given solution vector x
"""
function FormResidual!(cf,cx, args...)
    if typeof(cx) <: Ptr{Nothing}
        # When this routine is called from PETSc, cx is a pointer to a global vector
        # That's why we have to transfer it first to 
        x   =   PETSc.unsafe_localarray(PETSc.scalartype(petsclib),cx, write=false)
    else
        x   = cx;
    end
    if typeof(cf) <: Ptr{Nothing}
        f   =   PETSc.unsafe_localarray(PETSc.scalartype(petsclib),cf, write=true)
    else
        f   = cf;
    end
    n       =   length(x);
    xp      =   LinRange(0.0,1.0, n);
    F       =   6.0.*xp .+ (xp .+1.e-12).^6.0;      # define source term function
    
    dx      =   1.0/(n-1.0);
    f[1]    =   x[1] - 0.0;
    for i=2:n-1
        f[i] = (x[i-1] - 2.0*x[i] + x[i+1])/dx^2 + x[i]*x[i] - F[i]
    end
    f[n]    =   x[n] - 1.0;
    Base.finalize(x)
    Base.finalize(f)

end


"""
    Computes the jacobian, given solution vector x
"""
function FormJacobian!(cx, args...)

    if typeof(cx) <: Ptr{Nothing}
        x   =   PETSc.unsafe_localarray(PETSc.scalartype(petsclib),cx, write=false)
    else
        x   =   cx;
    end

    J   =   args[1];        # preconditioner = args[2], in case we want it to be different from J
    n   =   length(x);
    dx  =   1.0/(n-1.0);
    
    # interior points (hand-coded jacobian)
    for i=2:n-1
        J[i,i-1] = 1.0/dx^2;
        J[i,i  ] = -2.0/dx^2 + 2.0*x[i];
        J[i,i+1] = 1.0/dx^2;
    end

    # boundary points
    J[1,1] = 1.0;
    J[n,n] = 1.0;
  
    if typeof(J) <: PETSc.AbstractMat
        PETSc.assemble(J);  # finalize assembly
    
    end

    Base.finalize(x)
end


# ==========================================
# Main code 


# Compute initial solution
n   =   21;
F   =   SetInitialArrays(n);
x   =   zeros(n);

FormInitialGuess!(x);

# Compute initial jacobian using a julia structure to obtain the nonzero structure
# Note that we can also obtain this structure in a different manner
Jstruct  = zeros(n,n);
FormJacobian!(x, Jstruct);                              # jacobian in julia form
Jsp      =   sparse(Float64.(abs.(Jstruct) .> 0))       # sparse julia, with 1.0 in nonzero spots
PJ       =   PETSc.MatSeqAIJ(Jsp);                      # transfer to 

# Setup snes
x_s = PETSc.VecSeq(x);                  # solution vector
res = PETSc.VecSeq(F);     # residual vector

S = PETSc.SNES{Float64}(PETSc.petsclibs[1],MPI.COMM_WORLD; 
        snes_rtol=1e-12, 
        snes_monitor=false,
        snes_converged_reason=false);
PETSc.setfunction!(S, FormResidual!, res)
PETSc.setjacobian!(S, FormJacobian!, PJ, PJ)

# solve
PETSc.solve!(x_s, S);

# Extract & plot solution
x_sol = x_s.array;                  # convert solution to julia format
FormResidual!(res.array,x_sol)      # just for checking, compute residual

@show norm(res.array)

PETSc.finalize(petsclib)

# plot solution in REPL
lineplot(LinRange(0,1,n),x_sol,xlabel="width",ylabel="solution")
