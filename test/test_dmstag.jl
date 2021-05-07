using Test
using PETSc, MPI

if ~MPI.Initialized()
    MPI.Init()
end
PETSc.initialize()

#@testset "DMSTAG routines" begin

# Create 1D DMStag
dm = PETSc.DMStagCreate1d(MPI.COMM_SELF,PETSc.DM_BOUNDARY_NONE,20,2,2,PETSc.DMSTAG_STENCIL_BOX,2)
PETSc.destroy(dm)

# Create 1D DMStag with array of local @ of points
dm = PETSc.DMStagCreate1d(MPI.COMM_SELF,PETSc.DM_BOUNDARY_NONE,20,2,2,PETSc.DMSTAG_STENCIL_BOX,2,[20])

# Test get size
@test PETSc.DMStagGetGlobalSizes(dm) == 20
@test PETSc.DMStagGetLocalSizes(dm) == 20

# Test gettype
@test PETSc.gettype(dm) == "stag"               

# Info about ranks
@test PETSc.DMStagGetIsFirstRank(dm) == (true,false,false)
@test PETSc.DMStagGetIsLastRank(dm) == (true,false,false)

# Boundary
@test PETSc.DMStagGetBoundaryTypes(dm)==PETSc.DM_BOUNDARY_NONE

# Corners
@test PETSc.DMStagGetCorners(dm) == ((0,), (20,), (1,))

# DOF
@test PETSc.DMStagGetDOF(dm) == (2,2)

# Destroy
PETSc.destroy(dm)

# Create new struct and pass keyword arguments
dm_1D = PETSc.DMStagCreate1d(MPI.COMM_SELF,PETSc.DM_BOUNDARY_NONE,200,2,2; stag_grid_x=10);
@test PETSc.DMStagGetGlobalSizes(dm_1D) == 10

dm_2D = PETSc.DMStagCreate2d(MPI.COMM_SELF,PETSc.DM_BOUNDARY_NONE,PETSc.DM_BOUNDARY_NONE,20,21,1,1,1,1,1,PETSc.DMSTAG_STENCIL_BOX,2)
@test PETSc.DMStagGetGlobalSizes(dm_2D) == (20, 21)

dm_3D = PETSc.DMStagCreate3d(MPI.COMM_SELF,PETSc.DM_BOUNDARY_NONE,PETSc.DM_BOUNDARY_NONE,PETSc.DM_BOUNDARY_NONE,20,21,22,1,1,1,2,2,2,2,PETSc.DMSTAG_STENCIL_BOX,1,[],[],[])
@test PETSc.DMStagGetGlobalSizes(dm_3D) == (20, 21, 22)

# copy struct
dmnew = PETSc.DMStagCreateCompatibleDMStag(dm_3D,1,1,2,2)
@test PETSc.DMStagGetGlobalSizes(dmnew) == (20, 21, 22)

# Set coordinates 
PETSc.DMStagSetUniformCoordinates(dm_1D, 0, 10)

# Stencil width
@test  PETSc.DMStagGetStencilWidth(dm_1D)==2

# retrieve DM with coordinates
#subDM = PETSc.DMProductGetDM(dm_1D, 0)

# retrieve coordinate and value slots
#@test PETSc.DMStagGetProductCoordinateLocationSlot(dm, PETSc.DMSTAG_RIGHT) == 1
#@test PETSc.DMStagGetLocationSlot(dm_1D, PETSc.DMSTAG_RIGHT, 0) ==4

# Create a global and local Vec from the DMStag
vec_test_global     = PETSc.DMCreateGlobalVector(dm_1D)
vec_test            = PETSc.DMCreateLocalVector(dm_1D)
vec_test_2D         = PETSc.DMCreateLocalVector(dm_2D)

# Simply extract an array from the local vector
#x = PETSc.unsafe_localarray(Float64, vec_test.ptr; read=true, write=false)

entriesPerElement = PETSc.DMStagGetEntriesPerElement(dm_1D)

x,m = PETSc.DMStagGetGhostCorners(dm_1D)

@test PETSc.DMStagGetStencilType(dm_1D)==PETSc.DMSTAG_STENCIL_BOX 

# VEC test
# testing how to set values in a local vector:
#
# Note; this test really belongs to a Vec test & should be pushed to a different test file
v       =   rand(10)
v[10]   =   1;
V       =   PETSc.VecSeq(v)
@test V[10] == 1

# VEC test
# create a local Julia array from the vector which we can modify (write=true)
x_local =   PETSc.unsafe_localarray(Float64, V.ptr, write=true);    # create a local array from the vector
x_local[8:10] .= x_local[8:10]*2 .+ 100                             # modify the julia array
finalize(x_local)                                                   # delete local array after local use
@test v[10] == 102                                                  # check

# Note: What I don't understand is that even in the case that we read the array
# as read-only, changing the values in the julia array modifies them in the PetscVec 
# (that seems to defy the purpose of having a read-only option)
#
# In practice this is likely not hugely important; we should simply keep in mind to not 
# change the values locally

# Test retrieving an array from the DMStag:
X = PETSc.DMStagVecGetArray(dm_2D,vec_test_2D);
X[1,1,1] = 1;

# See if DMLocalToGlobal works
vec_test_global .= 0;
vec_test        .= 0;
vec_test[1:end] = 1:length(vec_test);
PETSc.DMLocalToGlobal(dm_1D, vec_test, PETSc.INSERT_VALUES, vec_test_global)
@test vec_test_global[20]==20

# test GlobalToLocal as well. 
# NOTE: as we currently only have VecSeq, parallel halos are not yet tested with this

# Test DMStagVecGetArray for a 1D case
vec_test.array[1:10] = 1:10
X_1D = PETSc.DMStagVecGetArray(dm_1D,vec_test);
@test X_1D[2,3] == 7.0

# Create two stencil locations
pos1 = PETSc.DMStagStencil(PETSc.DMSTAG_LEFT,1,0,0,1)
@test pos1.c == 1
pos2 = PETSc.DMStagStencil(PETSc.DMSTAG_RIGHT,4,0,0,0)
@test pos2.loc == PETSc.DMSTAG_RIGHT
@test pos2.i == 4


# Retrieve value from stencil
val = PETSc.DMStagVecGetValueStencil(dm_1D, vec_test, pos1) # this gets a single value
@test val==6

# Set single value in global vector using stencil
PETSc.DMStagVecSetValueStencil(dm_1D, vec_test_global, pos2, 2222.2, PETSc.INSERT_VALUES)
@test vec_test_global[21] == 2222.2

pos3 = PETSc.DMStagStencil_c(PETSc.DMSTAG_LEFT,1,0,0,1)

# NOTE: setting/getting multiple values is somehow not working for me. Can be called
#  by creating a wrapper
#val = PETSc.DMStagVecGetValuesStencil(dm_1D, vec_test, [pos3; pos3]) 


# Create matrix from dm object, Note: can only be viewed once it is assembled!
A = PETSc.DMCreateMatrix(dm_1D);  # 
@test size(A) == (42,42)
PETSc.assembled(A)

# set some values using normal indices:
A[1,1]= 1.0
A[1,10]= 1.0

# Set values using the DMStagStencil indices
PETSc.DMStagMatSetValueStencil(dm_1D, A, pos1, pos1, 11.1, PETSc.INSERT_VALUES)

# Assemble matrix
PETSc.assemble(A)
@test A[1,10] == 1.0 

# Reads a value from the matrix, using the stencil structure
@test PETSc.DMStagMatGetValueStencil(dm_1D, A, pos1, pos1)==11.1

# Info about ranks
@test PETSc.DMStagGetNumRanks(dm_1D)==1
@test PETSc.DMStagGetLocationSlot(dm_1D, PETSc.DMSTAG_LEFT,1)  == 1

#PETSc.DMStagVecGetValuesStencil(dm_1D, vec_test.ptr, [pos2]) # this sets a single valu

#PETSc.DMStagVecGetValuesStencil(dm_1D, vec_test.ptr, [pos1; pos2])

# testing different ways to retrieve/set values
vec_2D  = PETSc.DMCreateLocalVector(dm_2D)
vec_2D .= 0.0;



# Make a loop over all points 
PETSc.destroy(dm_2D);


dofCenter       =   1;
dofEdge         =   1;
dofVertex       =   0
stencilWidth    =   1;
dm_2D = PETSc.DMStagCreate2d(MPI.COMM_SELF,
                                PETSc.DM_BOUNDARY_GHOSTED,
                                PETSc.DM_BOUNDARY_GHOSTED,
                                10,11,
                                PETSc.PETSC_DECIDE,PETSc.PETSC_DECIDE,
                                dofVertex,dofEdge,dofCenter,
                                PETSc.DMSTAG_STENCIL_BOX,stencilWidth)

vec_test_2D_global      =   PETSc.DMCreateGlobalVector(dm_2D)
vec_test_2D_local       =   PETSc.DMCreateLocalVector(dm_2D)

nStart, nEnd, nExtra    =   PETSc.DMStagGetCorners(dm_2D)
#nStart, nEnd            =   PETSc.DMStagGetGhostCorners(dm_2D)

for ix=nStart[1]:nEnd[1]-1
    for iy=nStart[2]:nEnd[2]-1
        
        # DOF at the center point
        dof     = 0;
        pos     = PETSc.DMStagStencil(PETSc.DMSTAG_DOWN,ix,iy,0,dof)
        value   = ix+10; 
        PETSc.DMStagVecSetValueStencil(dm_2D, vec_test_2D_global, pos, value, PETSc.INSERT_VALUES)

        dof     = 0;
        pos     = PETSc.DMStagStencil(PETSc.DMSTAG_LEFT,ix,iy,0,dof)
        value   = 33; 
        PETSc.DMStagVecSetValueStencil(dm_2D, vec_test_2D_global, pos, value, PETSc.INSERT_VALUES)
        
        dof     = 0;
        pos     = PETSc.DMStagStencil(PETSc.DMSTAG_ELEMENT,ix,iy,0,dof)
        value   = 44; 
        PETSc.DMStagVecSetValueStencil(dm_2D, vec_test_2D_global, pos, value, PETSc.INSERT_VALUES)
        
      #  dof     = 0;
      #  pos     = PETSc.DMStagStencil(PETSc.DMSTAG_FRONT,ix,iy,0,dof)
      #  value   = 55; 
      #  PETSc.DMStagVecSetValueStencil(dm_2D, vec_test_2D_global, pos, value, PETSc.INSERT_VALUES)
        
    end
end
PETSc.assemble(vec_test_2D_global) # assemble global vector

PETSc.DMGlobalToLocal(dm_2D,vec_test_2D_global, PETSc.INSERT_VALUES,vec_test_2D_local)   # copy global 2 local vector and update ghost points
X2D_dofs = PETSc.DMStagVecGetArray(dm_2D,vec_test_2D_local)           # extract arrays with all DOF (mostly for visualizing)

# Retrieve a local array 
Xarray = PETSc.DMStagGetArrayLocationSlot(dm_2D,vec_test_2D_local, PETSc.DMSTAG_LEFT, 0)

@test sum(X2D_dofs[:,:,2]-Xarray)==0        # check if the local 


# retrieve value back from the local array and check that it agrees with the 
dof     = 0;
pos     = PETSc.DMStagStencil(PETSc.DMSTAG_DOWN,2,2,0,dof)
@test PETSc.DMStagVecGetValueStencil(dm_2D, vec_test_2D_local, pos) == 12.0

#PETSc.destroy(dm_2D)

# Construct a 1D test case for a diffusion solver, with 1 DOF @ the center
nx      =   50;
dm_1D   =   PETSc.DMStagCreate1d(MPI.COMM_SELF,PETSc.DM_BOUNDARY_NONE,nx,1,0);
v_g     =   PETSc.DMCreateGlobalVector(dm_1D)
v_l     =   PETSc.DMCreateLocalVector(dm_1D)

function Residual(x)

    # Retrieve an array with T @ vertex points
    #  NOTE: we stil need to work on the case that points are defined @ center points 
    T           =     PETSc.DMStagGetArrayLocationSlot(dm_1D,x, PETSc.DMSTAG_LEFT, 0); # includes ghost points
    
    n           =     length(T);    # array length
    f           =     zero(T)       # same type as x   
    
    # compute the FD stencil
    dx          =     1.0/(n-1);
    f[1]        =     T[1]-1.;                                  # left BC
    f[2:n-1]    =     (T[3:n] - 2*T[2:n-1] + T[1:n-2])/dx^2     # steady state diffusion
    f[n]        =     T[n]-10.;                                 # right BC

    return f
end

using ForwardDiff, SparseArrays
J           =       ForwardDiff.jacobian(Residual, (v_l.array));        # compute jacobian automatically
J           =       sparse(J);                                          # Create sparse matrix from this

A           =       PETSc.DMCreateMatrix(dm_1D);                        # extract (global) matrix from DMStag
A          .=       J;                                                  # set values in PETSc matrix

ksp         =       PETSc.KSP(A; ksp_rtol=1e-8, ksp_monitor=true)       # create KSP object
sol         =       PETSc.DMCreateGlobalVector(dm_1D);
rhs         =      -Residual(sol.array);                               # initial rhs vector

sol_julia   =       ksp\rhs;                                            # solve, using ksp




# NOT WORKING YET
#lx = zeros(Int32,1);
#ly = zeros(Int32,1);
#lz = zeros(Int32,1);
#PETSc.DMStagGetOwnershipRanges(dm_1D,lx,ly,lz)

#end

