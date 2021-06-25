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
@test PETSc.DMStagGetCorners(dm) == (0, 20, 1)

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

dm_ghosted = PETSc.DMStagCreate1d(MPI.COMM_SELF,PETSc.DM_BOUNDARY_GHOSTED,200,2,2; stag_grid_x=10);

# Set coordinates 
PETSc.DMStagSetUniformCoordinatesExplicit(dm_1D, 0, 10)
PETSc.DMStagSetUniformCoordinatesProduct(dm_3D, 0, 10, 0, 11, 0, 12)

# Stencil width
@test  PETSc.DMStagGetStencilWidth(dm_1D)==2

# retrieve DM with coordinates
DMcoord = PETSc.DMGetCoordinateDM(dm_1D)

# create coordinate local vector
vec_coord = PETSc.DMGetCoordinatesLocal(dm_1D);

# retrieve coordinate array (explicit)
X_coord = PETSc.DMStagVecGetArray(DMcoord, vec_coord);
@test X_coord[1,2] == 0.5

# retreive coordinate array (product)
#x_coord,y_coord,z_coord = PETSc.DMStagGetProductCoordinateArraysRead(dm_3D);

# retrieve coordinate and value slots
#@test PETSc.DMStagGetProductCoordinateLocationSlot(dm, PETSc.DMSTAG_RIGHT) == 1
@test PETSc.DMStagGetLocationSlot(dm_1D, PETSc.DMSTAG_RIGHT, 0) ==4
#g = PETSc.DMStagGetLocationSlot(dm_1D, PETSc.DMSTAG_RIGHT, 0)
# Create a global and local Vec from the DMStag
vec_test_global     = PETSc.DMCreateGlobalVector(dm_1D)
vec_test            = PETSc.DMCreateLocalVector(dm_1D)
vec_test_2D         = PETSc.DMCreateLocalVector(dm_2D)

# Simply extract an array from the local vector
#x = PETSc.unsafe_localarray(Float64, vec_test.ptr; read=true, write=false)

@test PETSc.DMGetDimension(dm_1D) == 1

@test PETSc.DMStagGetEntriesPerElement(dm_1D)==4

@test PETSc.DMStagGetGhostCorners(dm_1D)==(0,11)

ix,in = PETSc.DMStagGetCentralNodes(dm_ghosted);
@test ix[1] == 3

ind = PETSc.LocalInGlobalIndices(dm_ghosted);
@test ind[1] == 9

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
X[end,end,end] = 111;

@test vec_test_2D[end]==111.0     # check if modifying the array affects the vecror

Base.finalize(X)

Z = PETSc.DMStagVecGetArrayRead(dm_2D, vec_test_2D);
@test Z[end,end,end]==111.
# See if DMLocalToGlobal works
vec_test_global .= 0;
vec_test        .= 0;
vec_test[1:end] = 1:length(vec_test);
PETSc.DMLocalToGlobal(dm_1D, vec_test, PETSc.INSERT_VALUES, vec_test_global)
@test vec_test_global[20]==20

vec_test_global[1] = 42;

PETSc.DMGlobalToLocal(dm_1D,vec_test_global, PETSc.INSERT_VALUES,vec_test);
@test vec_test[1] == 42;

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

pos = [pos1, pos2];

# Retrieve value from stencil
val = PETSc.DMStagVecGetValuesStencil(dm_1D, vec_test, pos1) # this gets a single value
@test val==6
vals = PETSc.DMStagVecGetValuesStencil(dm_1D, vec_test, 2, pos) # this gets a single value
@test vals[1] == 6

# Set single value in global vector using stencil
val1 = [2222.2, 3.2];
PETSc.DMStagVecSetValuesStencil(dm_1D, vec_test_global, pos1, val1[1], PETSc.INSERT_VALUES)
@test vec_test_global[6] == 2222.2
PETSc.DMStagVecSetValuesStencil(dm_1D, vec_test_global, 2, pos, val1, PETSc.INSERT_VALUES)
@test vec_test_global[21] == 3.2



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
PETSc.DMStagMatSetValuesStencil(dm_1D, A, pos1, pos1, 11.1, PETSc.INSERT_VALUES)
PETSc.DMStagMatSetValuesStencil(dm_1D, A, 1, [pos2], 2, pos, val1, PETSc.INSERT_VALUES)

# Assemble matrix
PETSc.assemble(A)
@test A[1,10] == 1.0 

# Reads a value from the matrix, using the stencil structure
@test PETSc.DMStagMatGetValuesStencil(dm_1D, A, pos1, pos1)==11.1
@test PETSc.DMStagMatGetValuesStencil(dm_1D, A, 1, [pos2], 2, pos)==val1

# Info about ranks
@test PETSc.DMStagGetNumRanks(dm_1D)==1
@test PETSc.DMStagGetLocationSlot(dm_1D, PETSc.DMSTAG_LEFT,1)  == 1

#PETSc.DMStagVecGetValuesStencil(dm_1D, vec_test.ptr, [pos2]) # this gets a single valu

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
        PETSc.DMStagVecSetValuesStencil(dm_2D, vec_test_2D_global, pos, value, PETSc.INSERT_VALUES)

        dof     = 0;
        pos     = PETSc.DMStagStencil(PETSc.DMSTAG_LEFT,ix,iy,0,dof)
        value   = 33; 
        PETSc.DMStagVecSetValuesStencil(dm_2D, vec_test_2D_global, pos, value, PETSc.INSERT_VALUES)
        
        dof     = 0;
        pos     = PETSc.DMStagStencil(PETSc.DMSTAG_ELEMENT,ix,iy,0,dof)
        value   = 44; 
        PETSc.DMStagVecSetValuesStencil(dm_2D, vec_test_2D_global, pos, value, PETSc.INSERT_VALUES)
        
      #  dof     = 0;
      #  pos     = PETSc.DMStagStencil(PETSc.DMSTAG_FRONT,ix,iy,0,dof)
      #  value   = 55; 
      #  PETSc.DMStagVecSetValuesStencil(dm_2D, vec_test_2D_global, pos, value, PETSc.INSERT_VALUES)
        
    end
end
PETSc.assemble(vec_test_2D_global) # assemble global vector

PETSc.DMGlobalToLocal(dm_2D,vec_test_2D_global, PETSc.INSERT_VALUES,vec_test_2D_local)   # copy global 2 local vector and update ghost points
X2D_dofs  = PETSc.DMStagVecGetArray(dm_2D,vec_test_2D_local)           # extract arrays with all DOF (mostly for visualizing)


# Retrieve a local array 
# Note: this still needs some work, as it currently does not link back anymore to the PETSc vector
Xarray = PETSc.DMStagGetGhostArrayLocationSlot(dm_2D,vec_test_2D_local, PETSc.DMSTAG_LEFT, 0)

@test sum(X2D_dofs[:,:,2]-Xarray)==0        # check if the local 

# retrieve value back from the local array and check that it agrees with the 
dof     = 0;
pos     = PETSc.DMStagStencil(PETSc.DMSTAG_DOWN,2,2,0,dof)
@test PETSc.DMStagVecGetValuesStencil(dm_2D, vec_test_2D_local, pos) == 12.0


# -----------------
# Example of SNES, with AD jacobian

# Define a struct that holds data we need in the local SNES routines below   
mutable struct Data
    dm
    x_l
    f_l
end
user_ctx = Data(nothing, nothing, nothing);  # holds data we need in the local 

# Construct a 1D test case for a diffusion solver, with 1 DOF @ the center
nx              =   21;
user_ctx.dm     =   PETSc.DMStagCreate1d(MPI.COMM_SELF,PETSc.DM_BOUNDARY_NONE,nx,1,1);
#user_ctx.dm     =   PETSc.DMStagCreate1d(MPI.COMM_SELF,PETSc.DM_BOUNDARY_GHOSTED,nx,1,1, PETSc.DMSTAG_STENCIL_BOX,1);


x_g             =   PETSc.DMCreateGlobalVector(user_ctx.dm)
f_g             =   PETSc.DMCreateGlobalVector(user_ctx.dm)
user_ctx.x_l    =   PETSc.DMCreateLocalVector(user_ctx.dm)
user_ctx.f_l    =   PETSc.DMCreateLocalVector(user_ctx.dm)


function FormRes!(cfx_g, cx_g, user_ctx)

    # Note that in PETSc, cx and cfx are pointers to global vectors. 
    
    # Copy global to local vectors
    PETSc.DMGlobalToLocal(user_ctx.dm, cx_g,  PETSc.INSERT_VALUES,  user_ctx.x_l) 
    PETSc.DMGlobalToLocal(user_ctx.dm, cfx_g, PETSc.INSERT_VALUES,  user_ctx.f_l) 

    # Retrieve arrays from the local vectors
    ArrayLocal_x     =   PETSc.DMStagVecGetArrayRead(user_ctx.dm, user_ctx.x_l);  # array with all local x-data
    ArrayLocal_f     =   PETSc.DMStagVecGetArray(user_ctx.dm, user_ctx.f_l);      # array with all local residual
    
    # Compute local residual 
    ComputeLocalResidual(user_ctx.dm, ArrayLocal_x, ArrayLocal_f, user_ctx)

    # Finalize local arrays
    Base.finalize(ArrayLocal_x)
    Base.finalize(ArrayLocal_f)

    # Copy local into global residual vector
    PETSc.DMLocalToGlobal(user_ctx.dm,user_ctx.f_l, PETSc.INSERT_VALUES, cfx_g) 

end

function ComputeLocalResidual(dm, ArrayLocal_x, ArrayLocal_f, user_ctx)
    # Compute the local residual. The vectors include ghost points 

    T              =   PETSc.DMStagGetGhostArrayLocationSlot(dm,ArrayLocal_x, PETSc.DMSTAG_LEFT,    0); 
    fT             =   PETSc.DMStagGetGhostArrayLocationSlot(dm,ArrayLocal_f, PETSc.DMSTAG_LEFT,    0); 
    
    P              =   PETSc.DMStagGetGhostArrayLocationSlot(dm,ArrayLocal_x, PETSc.DMSTAG_ELEMENT, 0); 
    fP             =   PETSc.DMStagGetGhostArrayLocationSlot(dm,ArrayLocal_f, PETSc.DMSTAG_ELEMENT, 0); 
     
    # compute the FD stencil
    sx, sn          =     PETSc.DMStagGetCentralNodes(dm);          # indices of (center/element) points, not including ghost values. 
    sx_g, nx_g      =     PETSc.DMStagGetGhostCorners(user_ctx.dm); # start and end of loop including ghost points
    s, n, e         =     PETSc.DMStagGetCorners(user_ctx.dm); # start and end of loop including ghost points

    nT             =     length(T);                                 # array length
    dx             =     1.0/(n[1]-1);   
    xp             =     (sx_g[1]:nx_g[1]).*dx;                     # coordinates including ghost points (to define source term)
    F              =     6.0.*xp .+ (xp .+1.e-12).^6.0;             # define source term function
     
    # Nonlinear equation @ nodal points
    ind            =     sx[1]:sn[1]+1;                             #  There is one more "vertex" point
    i              =     ind[2:end-1]                                   
    fT[ind[1]]     =     T[ind[1]  ]-0.5;                           # left BC
    fT[ind[end]]   =     T[ind[end]]-2.0;                           # right BC
    fT[i]          =     (T[i .+ 1] - 2*T[i] + T[i .- 1])/dx^2  + T[i].*T[i] - F[i] # NL diffusion with source term
    
    # second, non-coupled, equation @ center points
    ind            =     sx[1]:sn[1]+0;                             #  There is one more "vertex" point
    i              =     ind[2:end-1];                             
    fP[ind[1]]     =     P[ind[1]]-30.;                             # left BC
    fP[ind[end]]   =     P[ind[end]]-20.;                           # right BC
    fP[i]          =     (P[i .+ 1] - 2*P[i] + P[i .- 1])/dx^2      # steady state diffusion

end

function  ForwardDiff_res(x, user_ctx)
    f   = zero(x)               # vector of zeros, of same type as x (local vector)

    ArrayLocal_x     =   PETSc.DMStagVecGetArray(user_ctx.dm, x);        # array with all local x-data
    ArrayLocal_f     =   PETSc.DMStagVecGetArray(user_ctx.dm, f);        # array with all local residual
  
    ComputeLocalResidual(user_ctx.dm, ArrayLocal_x, ArrayLocal_f, user_ctx);

    # As the residual vector f is linked with ArrayLocal_f, we don't need to pass ArrayLocal_f back

    return f;
end

function FormJacobian!(cx_g, J, P, user_ctx)
    # This requires several steps:
    #
    #   1) Extract local vector from global solution (x) vector
    #   2) Compute local jacobian from the residual routine (note that
    #       this routine requires julia vectors as input)

    # Extract the local vector
    PETSc.DMGlobalToLocal(user_ctx.dm, cx_g,  PETSc.INSERT_VALUES,  user_ctx.x_l) 
    x               =   PETSc.unsafe_localarray(Float64, user_ctx.x_l.ptr;  write=false, read=true)

    f_Residual      =   (x -> ForwardDiff_res(x, user_ctx));        # pass additional arguments into the routine

    J_julia         =   ForwardDiff.jacobian(f_Residual,x);  

    # Note: since x is the LOCAL vector, J_julia also ends up having the same size.
    ind             =   PETSc.LocalInGlobalIndices(user_ctx.dm);
    J              .=   sparse(J_julia[ind,ind]);       

   return J_julia, ind
end

# Main SNES part
using ForwardDiff, SparseArrays
PJ           =      PETSc.DMCreateMatrix(user_ctx.dm);                  # extract (global) matrix from DMStag

julia_vec    =      0;
S = PETSc.SNES{Float64}(MPI.COMM_SELF, julia_vec; 
        snes_rtol=1e-12, 
        snes_monitor=true, 
        pc_type="none",
        snes_monitor_true_residual=true, 
        snes_converged_reason=true);
S.user_ctx  =       user_ctx;

PETSc.setfunction!(S, FormRes!, f_g)
PETSc.setjacobian!(S, FormJacobian!, PJ, PJ)

# Solve
PETSc.solve!(x_g, S);

# check
@test x_g[4] ≈ 29.5
@test x_g[11] ≈ 0.6792 rtol=1e-4


J_julia = FormJacobian!(x_g.ptr, PJ, PJ, user_ctx)

#
# -----------------


# -----------------
# 2D example
dofVertex   =   0
dofEdge     =   0
dofCenter   =   1
nx,nz       =   14,25
user_ctx.dm =   PETSc.DMStagCreate2d(MPI.COMM_SELF,PETSc.DM_BOUNDARY_GHOSTED,PETSc.DM_BOUNDARY_NONE,nx,nz,1,1,dofVertex,dofEdge,dofCenter,PETSc.DMSTAG_STENCIL_BOX,1)
PJ           =      PETSc.DMCreateMatrix(user_ctx.dm);                  # extract (global) matrix from DMStag
x_g             =   PETSc.DMCreateGlobalVector(user_ctx.dm)
f_g             =   PETSc.DMCreateGlobalVector(user_ctx.dm)
user_ctx.x_l    =   PETSc.DMCreateLocalVector(user_ctx.dm)
user_ctx.f_l    =   PETSc.DMCreateLocalVector(user_ctx.dm)


function ComputeLocalResidual(dm, ArrayLocal_x, ArrayLocal_f, user_ctx)
    # Compute the local residual. The vectors include ghost points 

    T              =   PETSc.DMStagGetGhostArrayLocationSlot(dm,ArrayLocal_x, PETSc.DMSTAG_LEFT,    0); 
    fT             =   PETSc.DMStagGetGhostArrayLocationSlot(dm,ArrayLocal_f, PETSc.DMSTAG_LEFT,    0); 
    
   # P              =   PETSc.DMStagGetGhostArrayLocationSlot(dm,ArrayLocal_x, PETSc.DMSTAG_ELEMENT, 0); 
   # fP             =   PETSc.DMStagGetGhostArrayLocationSlot(dm,ArrayLocal_f, PETSc.DMSTAG_ELEMENT, 0); 
     
    # compute the FD stencil
    sx, sn          =     PETSc.DMStagGetCentralNodes(dm);          # indices of (center/element) points, not including ghost values. 
    s, n, e         =     PETSc.DMStagGetCorners(user_ctx.dm);      # start and end of loop including ghost points

    nT             =     length(T);                                 # array length
    dx             =     1.0/(n[1]-1);   
    dz             =     1.0/(n[2]-1);   
    
    # set Ghost points for BC'S
    bnd            =    PETSc.DMStagGetBoundaryTypes(user_ctx.dm) 
    if bnd[1] == PETSc.DM_BOUNDARY_GHOSTED
        T[1,:]     =    T[2,:];        # zero flux; dT/dx=0
        T[end,:]   =    T[end-1,:];    # zero flux

        T[1,:]     =    T[end-1,:];        # zero flux; dT/dx=0
        T[end-1,:] =    T[end-1,:];    # zero flux   
    end
  
    # Diffusion @ center points
    indx           =     sx[1]:sn[1];                             #  There is one more "vertex" point
    indz           =     sx[2]:sn[2];                             
    ix             =     indx[1:end]                             # use ghost points in x         
    iz             =     indz[2:end-1]         
    fT[:,indz[1]]   =    T[:,indz[1]  ] .- 0.5;                             # bottom BC
    fT[:,indz[end]] =    T[:,indz[end]] .- 2.0;                             # top BC

    fT[ix,iz]       =    (T[ix .+ 1,iz] - 2*T[ix,iz] + T[ix .- 1,iz])/dx^2   + 
                         (T[ix,iz .+ 1] - 2*T[ix,iz] + T[ix,iz .- 1])/dz^2 
    
    # second, non-coupled, equation @ center points
    #ind            =     sx[1]:sn[1]+0;                             #  There is one more "vertex" point
    #i              =     ind[2:end-1] 
    #fP[ind[1]]     =     P[ind[1]]-30.;                             # left BC
    #fP[ind[end]]   =     P[ind[end]]-20.;                           # right BC
    #fP[i]          =     (P[i .+ 1] - 2*P[i] + P[i .- 1])/dx^2      # steady state diffusion

end

julia_vec    =      0;
S = PETSc.SNES{Float64}(MPI.COMM_SELF, julia_vec; 
        snes_rtol=1e-12, 
        snes_monitor=true, 
        pc_type="none",
        snes_monitor_true_residual=true, 
        snes_converged_reason=true);
S.user_ctx  =       user_ctx;

PETSc.setfunction!(S, FormRes!, f_g)
PETSc.setjacobian!(S, FormJacobian!, PJ, PJ)

# Solve 2D system
PETSc.solve!(x_g, S);

T2d =   PETSc.DMStagGetGhostArrayLocationSlot(user_ctx.dm,user_ctx.x_l, PETSc.DMSTAG_LEFT,    0); 

@test T2d[5,5] ≈ 0.75 rtol=1e-3
#
# -----------------

# NOT WORKING YET - we do however need this in parallel
#lx = zeros(Int32,1);
#ly = zeros(Int32,1);
#lz = zeros(Int32,1);
#PETSc.DMStagGetOwnershipRanges(dm_1D,lx,ly,lz)



