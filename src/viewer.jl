const CPetscViewer = Ptr{Cvoid}

"""
    AbstractViewer{PetscLib <: PetscLibType}

Abstract type of PETSc viewer.

# External Links
$(_doc_external("Viewer/PetscViewer"))
"""
abstract type AbstractViewer{PetscLib <: PetscLibType} end

"""
    ViewerStdout(petsclib, comm = MPI.COMM_SELF)

Create an ASCII `PetscViewer` for the `comm`

# External Links
$(_doc_external("Viewer/PETSC_VIEWER_STDOUT_"))
"""
mutable struct ViewerStdout{PetscLib} <: AbstractViewer{PetscLib}
    ptr::CPetscViewer
    comm::MPI.Comm
end

@for_petsc function ViewerStdout(
    ::$UnionPetscLib,
    comm::MPI.Comm,
)
    ptr = ccall(
        (:PETSC_VIEWER_STDOUT_, $petsc_library),
        CPetscViewer,
        (MPI.MPI_Comm,),
        comm,
    )
    return ViewerStdout{$PetscLib}(ptr, comm)
end

@for_petsc function Base.push!(
    viewer::AbstractViewer{$PetscLib},
    format::PetscViewerFormat,
)
    @chk ccall(
        (:PetscViewerPushFormat, $petsc_library),
        PetscErrorCode,
        (CPetscViewer, PetscViewerFormat),
        viewer,
        format,
    )
    return nothing
end

@for_petsc function Base.pop!(viewer::AbstractViewer{$PetscLib})
    @chk ccall(
        (:PetscViewerPopFormat, $petsc_library),
        PetscErrorCode,
        (CPetscViewer,),
        viewer,
    )
    return nothing
end

function with(f, viewer::AbstractViewer, format::PetscViewerFormat)
    push!(viewer, format)
    try
        f()
    finally
        pop!(viewer)
    end
end

# ideally we would capture the output directly, but this looks difficult
# easiest option is to redirect stdout
# based on suggestion from https://github.com/JuliaLang/julia/issues/32567
function _show(io::IO, obj)
    old_stdout = stdout
    try
        rd, = redirect_stdout()
        view(obj)
        Libc.flush_cstdio()
        flush(stdout)
        write(io, readavailable(rd))
    finally
        redirect_stdout(old_stdout)
    end
    return nothing
end

#=
# PETSc_jll isn't built with X support
mutable struct ViewerDraw <: AbstractViewer
    ptr::CPetscViewer
    comm::MPI.Comm
end
function ViewerDraw(comm::MPI.Comm)
    ptr = ccall((:PETSC_VIEWER_DRAW_, libpetsc), CPetscViewer, (MPI.MPI_Comm,), comm)
    return ViewerDraw(ptr, comm)
end
=#
