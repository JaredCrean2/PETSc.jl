
const CSNES = Ptr{Cvoid}
const CSNESType = Cstring


mutable struct SNES{T}
    ptr::CSNES
    comm::MPI.Comm
    opts::Options{T}
    fn!
    fn_vec
    update_jac!
    jac_A
    jac_P
    julia_vec::Cint 
    user_ctx
end


scalartype(::SNES{T}) where {T} = T

Base.cconvert(::Type{CSNES}, obj::SNES) = obj.ptr
Base.unsafe_convert(::Type{Ptr{CSNES}}, obj::SNES) =
    convert(Ptr{CSNES}, pointer_from_objref(obj))

Base.eltype(::SNES{T}) where {T} = T


# How to handle Jacobians?
#  - https://www.mcs.anl.gov/petsc/petsc-current/docs/manualpages/SNES/SNESComputeJacobianDefault.html
#  - https://www.mcs.anl.gov/petsc/petsc-current/docs/manualpages/SNES/SNESComputeJacobianDefaultColor.html
#  -

struct SNESFn{T}
end

struct SNESJac{T}
end
struct SNESFn_julia{T}
end
struct SNESJac_julia{T}
end


#=
Note: in parallel, cx/cfx should be global vectors

function _snesfn(csnes::CSNES, cx::CVec, cfx::CVec, ctx::Ptr{Cvoid})
    snes = unsafe_pointer_to_objref(ctx)
    snes.Feval(cfx, cx)
end

function _snesjac(csnes::CSNES, cx::CVec, cAmat::CMat, cPmat::CMat, ctx::Ptr{Cvoid})
    snes = unsafe_pointer_to_objref(ctx)
    snes.Jeval(cAmat, cPmat, cx)
end
=#

@for_libpetsc begin

    function SNES{$PetscScalar}(comm::MPI.Comm, julia_vec=1; kwargs...)
        initialize($PetscScalar)
        opts = Options{$PetscScalar}(kwargs...)
        snes = SNES{$PetscScalar}(C_NULL, comm, opts, nothing, nothing, nothing, nothing, nothing,julia_vec,nothing)
        @chk ccall((:SNESCreate, $libpetsc), PetscErrorCode, (MPI.MPI_Comm, Ptr{CSNES}), comm, snes)

        with(snes.opts) do
            setfromoptions!(snes)
        end

        if comm == MPI.COMM_SELF
            finalizer(destroy, snes)
        end
        return snes
    end


    function (::SNESFn{$PetscScalar})(csnes::CSNES, cx::CVec, cfx::CVec, ctx::Ptr{Cvoid})::$PetscInt
        snes = unsafe_pointer_to_objref(ctx)

        if snes.julia_vec==1    # we pass julia vecs
            x = unsafe_localarray($PetscScalar, cx; write=false)
            fx = unsafe_localarray($PetscScalar, cfx; read=false)
            snes.fn!(fx, x, snes.user_ctx)
            Base.finalize(x)
            Base.finalize(fx)
        else                    # pass pointers to PETSc vectors
            snes.fn!(cfx, cx, snes.user_ctx)
        end
        return $PetscInt(0)
    end


    function setfunction!(snes::SNES{$PetscScalar}, fn!, vec::AbstractVec{$PetscScalar})
        ctx = pointer_from_objref(snes)
        fptr = @cfunction(SNESFn{$PetscScalar}(), $PetscInt, (CSNES, CVec, CVec, Ptr{Cvoid}))
        with(snes.opts) do
            @chk ccall((:SNESSetFunction, $libpetsc), PetscErrorCode,
                (CSNES, CVec, Ptr{Cvoid}, Ptr{Cvoid}),
                snes, vec, fptr, ctx)
        end
        snes.fn_vec = vec
        snes.fn! = fn!
        return nothing
    end

    
    function destroy(snes::SNES{$PetscScalar})
        finalized($PetscScalar) ||
            @chk ccall((:SNESDestroy, $libpetsc), PetscErrorCode, (Ptr{CSNES},), snes)
        return nothing
    end

    function setfromoptions!(snes::SNES{$PetscScalar})
        @chk ccall((:SNESSetFromOptions, $libpetsc), PetscErrorCode, (CSNES,), snes)
    end

    function gettype(snes::SNES{$PetscScalar})
        t_r = Ref{CSNESType}()
        @chk ccall((:SNESGetType, $libpetsc), PetscErrorCode, (CSNES, Ptr{CSNESType}), snes, t_r)
        return unsafe_string(t_r[])
    end

    function view(snes::SNES{$PetscScalar}, viewer::Viewer{$PetscScalar}=ViewerStdout{$PetscScalar}(snes.comm))
        @chk ccall((:SNESView, $libpetsc), PetscErrorCode,
                    (CSNES, CPetscViewer),
                snes, viewer);
        return nothing
    end

    function (::SNESJac{$PetscScalar})(csnes::CSNES, cx::CVec, cA::CMat, cP::CMat, ctx::Ptr{Cvoid})::$PetscInt
        snes = unsafe_pointer_to_objref(ctx)
        @assert snes.ptr == csnes
        @assert snes.jac_A.ptr == cA
        @assert snes.jac_P.ptr == cP
        
        if snes.julia_vec==1    # pass julia vecs
            x  = unsafe_localarray($PetscScalar, cx; write=false)
            snes.update_jac!(x, snes.jac_A, snes.jac_P, snes.user_ctx)
            Base.finalize(x)
        else                    # pass pointers to PETSc vectors
            snes.update_jac!(cx, snes.jac_A, snes.jac_P, snes.user_ctx)
        end

        return $PetscInt(0)
    end

    function setjacobian!(snes::SNES{$PetscScalar}, update_jac!, A::AbstractMat{$PetscScalar}, P::AbstractMat{$PetscScalar}=A)
        ctx = pointer_from_objref(snes)
        jacptr = @cfunction(SNESJac{$PetscScalar}(), $PetscInt, (CSNES, CVec, CMat, CMat, Ptr{Cvoid}))
        with(snes.opts) do
            @chk ccall((:SNESSetJacobian, $libpetsc), PetscErrorCode,
                (CSNES, CMat, CMat, Ptr{Cvoid}, Ptr{Cvoid}),
                snes, A, P, jacptr, ctx)
        end
        snes.update_jac! = update_jac!
        snes.jac_A = A
        snes.jac_P = P
        return nothing
    end

    function solve!(x::AbstractVec{$PetscScalar}, snes::SNES{$PetscScalar}, b::AbstractVec{$PetscScalar})
        with(snes.opts) do
            @chk ccall((:SNESSolve, $libpetsc), PetscErrorCode,
            (CSNES, CVec, CVec), snes, b, x)
        end
        return x
    end
    function solve!(x::AbstractVec{$PetscScalar}, snes::SNES{$PetscScalar})
        with(snes.opts) do
            @chk ccall((:SNESSolve, $libpetsc), PetscErrorCode,
            (CSNES, CVec, CVec), snes, C_NULL, x)
        end
        return x
    end


end

"""
Creates a SNES object

    Usage:
        snes = SNES{PetscScalar}(comm::MPI.Comm, julia_vec=1; kwargs...)

    Input:
        comm:       -   MPI communicator
        julia_vec   -   indicates whether we want to have julia vectors or pointers to the PETSc vectors 
                        within the update_jac! and fn! user routines. Julia vectors are fine on 1 core,
                        but on multiple cores the PETSc pointers are more useful as we operate on the local 
                        portion of the vector, but pass globa vectors in/out 
    Output:
        snes        -   the snes object
"""
snes

solve!(x::AbstractVector{T}, snes::SNES{T}) where {T} = parent(solve!(AbstractVec(x), snes))

Base.show(io::IO, snes::SNES) = _show(io, snes)
