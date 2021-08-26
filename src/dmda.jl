abstract type AbstractDMDA{PetscLib} <: AbstractDM{PetscLib} end

mutable struct DMDA{PetscLib} <: AbstractDMDA{PetscLib}
    ptr::CDM
    opts::Options{PetscLib}
    age::Int
end

mutable struct DMDAPtr{PetscLib} <: AbstractDMDA{PetscLib}
    ptr::CDM
    age::Int
    own::Bool
end

"""
    DMDA(
        petsclib::PetscLib
        comm::MPI.Comm,
        boundary_type::NTuple{D, DMBoundaryType},
        global_dim::NTuple{D, Integer},
        dof_per_node::Integer,
        stencil_width::Integer,
        stencil_type;
        points_per_proc::Tuple,
        processors::Tuple,
        setfromoptions = true,
        dmsetup = true,
        options...
    )

Creates a D-dimensional distributed array with the options specified using
keyword arguments.

If keyword argument `points_per_proc[k] isa Vector{petsclib.PetscInt}` then this
specifies the points per processor in dimension `k`.

If keyword argument `processors[k] isa Integer` then this specifies the number of
processors used in dimension `k`; ignored when `D == 1`.

If keyword argument `setfromoptions == true` then `setfromoptions!` called.

If keyword argument `dmsetup == true` then `setup!` is called.

When `D == 1` the `stencil_type` argument is not required and ignored if
specified.

# External Links
$(_doc_external("DMDA/DMDACreate1d"))
$(_doc_external("DMDA/DMDACreate2d"))
$(_doc_external("DMDA/DMDACreate3d"))
"""
function DMDA(
    petsclib::PetscLib,
    comm::MPI.Comm,
    boundary_type::NTuple{1, DMBoundaryType},
    global_dim::NTuple{1, Integer},
    dof_per_node::Integer,
    stencil_width::Integer,
    stencil_type = nothing;
    points_per_proc::Tuple = (nothing,),
    processors = nothing,
    setfromoptions = true,
    dmsetup = true,
    options...,
) where {PetscLib}
    opts = Options(petsclib; options...)
    da = DMDA{PetscLib}(C_NULL, opts, petsclib.age)

    @assert length(points_per_proc) == 1

    ref_points_per_proc =
        if isnothing(points_per_proc[1]) || points_per_proc[1] == PETSC_DECIDE
            C_NULL
        else
            @assert points_per_proc[1] isa Array{PetscLib.PetscInt}
            @assert length(points_per_proc[1]) == MPI.Comm_size(comm)
            points_per_proc[1]
        end

    with(da.opts) do
        LibPETSc.DMDACreate1d(
            PetscLib,
            comm,
            boundary_type[1],
            global_dim[1],
            dof_per_node,
            stencil_width,
            ref_points_per_proc,
            da,
        )
    end
    setfromoptions && setfromoptions!(da)
    dmsetup && setup!(da)

    # We can only let the garbage collect finalize when we do not need to
    # worry about MPI (since garbage collection is asyncronous)
    if MPI.Comm_size(comm) == 1
        finalizer(destroy, da)
    end
    return da
end

function DMDA(
    petsclib::PetscLib,
    comm::MPI.Comm,
    boundary_type::NTuple{2, DMBoundaryType},
    global_dim::NTuple{2, Integer},
    dof_per_node::Integer,
    stencil_width::Integer,
    stencil_type;
    points_per_proc::Tuple = (nothing, nothing),
    processors::Tuple = (PETSC_DECIDE, PETSC_DECIDE),
    setfromoptions = true,
    dmsetup = true,
    options...,
) where {PetscLib}
    opts = Options(petsclib; options...)
    da = DMDA{PetscLib}(C_NULL, opts, petsclib.age)

    @assert length(points_per_proc) == 2

    ref_points_per_proc = ntuple(2) do d
        if isnothing(points_per_proc[d]) || points_per_proc[d] == PETSC_DECIDE
            C_NULL
        else
            @assert points_per_proc[d] isa Array{PetscLib.PetscInt}
            @assert length(points_per_proc[d]) == MPI.Comm_size(comm)
            points_per_proc[d]
        end
    end

    with(da.opts) do
        LibPETSc.DMDACreate2d(
            PetscLib,
            comm,
            boundary_type[1],
            boundary_type[2],
            stencil_type,
            global_dim[1],
            global_dim[2],
            processors[1],
            processors[2],
            dof_per_node,
            stencil_width,
            ref_points_per_proc[1],
            ref_points_per_proc[2],
            da,
        )
    end
    setfromoptions && setfromoptions!(da)
    dmsetup && setup!(da)

    # We can only let the garbage collect finalize when we do not need to
    # worry about MPI (since garbage collection is asyncronous)
    if MPI.Comm_size(comm) == 1
        finalizer(destroy, da)
    end
    return da
end

function DMDA(
    petsclib::PetscLib,
    comm::MPI.Comm,
    boundary_type::NTuple{3, DMBoundaryType},
    global_dim::NTuple{3, Integer},
    dof_per_node::Integer,
    stencil_width::Integer,
    stencil_type;
    points_per_proc::Tuple = (nothing, nothing, nothing),
    processors::Tuple = (PETSC_DECIDE, PETSC_DECIDE, PETSC_DECIDE),
    setfromoptions = true,
    dmsetup = true,
    options...,
) where {PetscLib}
    opts = Options(petsclib; options...)
    da = DMDA{PetscLib}(C_NULL, opts, petsclib.age)

    @assert length(points_per_proc) == 3

    ref_points_per_proc = ntuple(3) do d
        if isnothing(points_per_proc[d]) || points_per_proc[d] == PETSC_DECIDE
            C_NULL
        else
            @assert points_per_proc[d] isa Array{PetscLib.PetscInt}
            @assert length(points_per_proc[d]) == MPI.Comm_size(comm)
            points_per_proc[d]
        end
    end

    with(da.opts) do
        LibPETSc.DMDACreate3d(
            PetscLib,
            comm,
            boundary_type[1],
            boundary_type[2],
            boundary_type[3],
            stencil_type,
            global_dim[1],
            global_dim[2],
            global_dim[3],
            processors[1],
            processors[2],
            processors[3],
            dof_per_node,
            stencil_width,
            ref_points_per_proc[1],
            ref_points_per_proc[2],
            ref_points_per_proc[3],
            da,
        )
    end
    setfromoptions && setfromoptions!(da)
    dmsetup && setup!(da)

    # We can only let the garbage collect finalize when we do not need to
    # worry about MPI (since garbage collection is asyncronous)
    if MPI.Comm_size(comm) == 1
        finalizer(destroy, da)
    end
    return da
end

"""
    getinfo(da::AbstractDMDA)

Get the info associated with the distributed array `da`. Returns `V` which has
fields

 - `dim`
 - `global_size` (`Tuple` of length 3)
 - `procs_per_dim` (`Tuple` of length 3)
 - `dof_per_node`
 - `boundary_type` (`Tuple` of length 3)
 - `stencil_width`
 - `stencil_type`

# External Links
$(_doc_external("DMDA/DMDAGetInfo"))
"""
function getinfo(da::AbstractDMDA{PetscLib}) where {PetscLib}
    PetscInt = PetscLib.PetscInt

    dim = [PetscInt(0)]
    glo_size = [PetscInt(0), PetscInt(0), PetscInt(0)]
    procs_per_dim = [PetscInt(0), PetscInt(0), PetscInt(0)]
    dof_per_node = [PetscInt(0)]
    stencil_width = [PetscInt(0)]
    boundary_type = [DM_BOUNDARY_NONE, DM_BOUNDARY_NONE, DM_BOUNDARY_NONE]
    stencil_type = [DMDA_STENCIL_STAR]

    LibPETSc.DMDAGetInfo(
        PetscLib,
        da,
        dim,
        Ref(glo_size, 1),
        Ref(glo_size, 2),
        Ref(glo_size, 3),
        Ref(procs_per_dim, 1),
        Ref(procs_per_dim, 2),
        Ref(procs_per_dim, 3),
        dof_per_node,
        stencil_width,
        Ref(boundary_type, 1),
        Ref(boundary_type, 2),
        Ref(boundary_type, 3),
        stencil_type,
    )

    return (
        dim = dim[1],
        global_size = (glo_size...,),
        procs_per_dim = (procs_per_dim...,),
        dof_per_node = dof_per_node[1],
        boundary_type = (boundary_type...,),
        stencil_width = stencil_width[1],
        stencil_type = stencil_type[1],
    )
end

"""
    getcorners(da::AbstractDMDA)

Returns a `NamedTuple` with the global indices (excluding ghost points) of the
`lower` and `upper` corners as well as the `size`.

# External Links
$(_doc_external("DMDA/DMDAGetCorners"))
"""
function getcorners(da::AbstractDMDA{PetscLib}) where {PetscLib}
    PetscInt = PetscLib.PetscInt
    corners = [PetscInt(0), PetscInt(0), PetscInt(0)]
    local_size = [PetscInt(0), PetscInt(0), PetscInt(0)]
    LibPETSc.DMDAGetCorners(
        PetscLib,
        da,
        Ref(corners, 1),
        Ref(corners, 2),
        Ref(corners, 3),
        Ref(local_size, 1),
        Ref(local_size, 2),
        Ref(local_size, 3),
    )
    corners .+= 1
    upper = corners .+ local_size .- PetscInt(1)
    return (
        lower = CartesianIndex(corners...),
        upper = CartesianIndex(upper...),
        size = (local_size...,),
    )
end

"""
    getghostcorners(da::AbstractDMDA)

Returns a `NamedTuple` with the global indices (including ghost points) of the
`lower` and `upper` corners as well as the `size`.

# External Links
$(_doc_external("DMDA/DMDAGetGhostCorners"))
"""
function getghostcorners(da::AbstractDMDA{PetscLib}) where {PetscLib}
    PetscInt = PetscLib.PetscInt
    corners = [PetscInt(0), PetscInt(0), PetscInt(0)]
    local_size = [PetscInt(0), PetscInt(0), PetscInt(0)]
    LibPETSc.DMDAGetGhostCorners(
        PetscLib,
        da,
        Ref(corners, 1),
        Ref(corners, 2),
        Ref(corners, 3),
        Ref(local_size, 1),
        Ref(local_size, 2),
        Ref(local_size, 3),
    )
    corners .+= 1
    upper = corners .+ local_size .- PetscInt(1)
    return (
        lower = CartesianIndex(corners...),
        upper = CartesianIndex(upper...),
        size = (local_size...,),
    )
end

"""
    similar(da::DMDA)

return an uninitialized `DMDA` struct.
"""
Base.empty(da::DMDA{PetscLib}) where {PetscLib} =
    DMDA{PetscLib}(C_NULL, da.opts, da.age)

"""
    setuniformcoordinates!(
        da::DMDA
        xyzmin::NTuple{N, Real},
        xyzmax::NTuple{N, Real},
    ) where {N}

Set uniform coordinates for the `da` using the lower and upper corners defined
by the `NTuple`s `xyzmin` and `xyzmax`. If `N` is less than the dimension of the
`da` then the value of the trailing coordinates is set to `0`.

# External Links
$(_doc_external("DMDA/DMDASetUniformCoordinates"))
"""
function setuniformcoordinates!(
    da::DMDA{PetscLib},
    xyzmin::NTuple{N, Real},
    xyzmax::NTuple{N, Real},
) where {N, PetscLib}
    PetscReal = PetscLib.PetscReal
    xmin = PetscReal(xyzmin[1])
    xmax = PetscReal(xyzmax[1])

    ymin = (N > 1) ? PetscReal(xyzmin[2]) : PetscReal(0)
    ymax = (N > 1) ? PetscReal(xyzmax[2]) : PetscReal(0)

    zmin = (N > 2) ? PetscReal(xyzmin[3]) : PetscReal(0)
    zmax = (N > 2) ? PetscReal(xyzmax[3]) : PetscReal(0)

    LibPETSc.DMDASetUniformCoordinates(
        PetscLib,
        da,
        xmin,
        xmax,
        ymin,
        ymax,
        zmin,
        zmax,
    )
    return da
end



"""
    getlocalcoordinatearray(da::AbstractDMDA)

Returns a `NamedTuple` with OffsetArrays that contain the local coordinates and that can be addressed uisng global indices

"""
function getlocalcoordinatearray(
    da::DMDA{PetscLib},
) where {PetscLib}

coord_vec = PETSc.coordinatesDMLocalVec(da);                # retrieve local coordinates
array1D   = PETSc.unsafe_localarray(coord_vec; read=true);  # array
dim       = [0];
LibPETSc.DMGetCoordinateDim(PetscLib, da, dim);
dim       = dim[1];
corners   = PETSc.getghostcorners(da);

X = reshapelocalarray(array1D[1:dim:end], da, ghost=true);                              # reshape into array with global numbering

Y,Z     = [],[];
if dim>1
    Y = reshapelocalarray(array1D[2:dim:end], da, ghost=true);                          # reshape into array with global numbering
end
if dim>2
    Z = reshapelocalarray(array1D[3:dim:end], da, ghost=true);                          # reshape into array with global numbering
end

return (X=X, 
        Y=Y,
        Z=Z)
end



"""
    getlocalarraydof(da::AbstractDMDA, l_x::Vector;  dof::Int64=1, ghost=true)

Returns a view of a local Array for the degree of freedom `dof`, given a local array l_x that may have ghost values (`ghost=true`) or not.
Note that in julia, the first degree of freedom is 1 (and not 0). 

"""
function getlocalarraydof(
    da::AbstractDM{PetscLib},
    l_x::Vector;
    dof::Int64=1,
    ghost=true,
) where {PetscLib}

    dof_da      = [1];
    LibPETSc.DMDAGetDof(PetscLib,da,dof_da);    # number of DOF that the DMDA has
    n           = length(l_x);
    Arr         = Base.view(l_x,dof:dof_da[1]:n)

    oArr = reshapelocalarray(Arr, da, ghost=ghost);    # reshape into array with global numbering

    return oArr
end


"""
    oArr = reshapelocalarray(Arr, da::AbstractDM{PetscLib}; ghost=false);

Reshapes a local vector `Arr` into an OffsetArray `oArr` that can be addressed using global ordering. `ghost` indicates whether the local vector contains ghost values 

"""
function reshapelocalarray(
    Arr,
    da::AbstractDM{PetscLib};
    ghost=false
) where {PetscLib}

    if ghost
        corners     = PETSc.getghostcorners(da);
    else
        corners     = PETSc.getcorners(da);
    end
    oArr = OffsetArray(
            reshape(Arr, Int64.(corners.size)...),
            (corners.lower[1]):(corners.upper[1]),
            (corners.lower[2]):(corners.upper[2]),
            (corners.lower[3]):(corners.upper[3]),
    )

    return oArr
end

