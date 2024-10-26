# EXCLUDE FROM TESTING
# FIXME: This is excluded because it is failing right now.

# This is an example of a 1D viscoelastic porosity wave as described in
# Vasyliev et al. Geophysical Research Letters (25), 17. p. 3239-3242
# https://agupubs.onlinelibrary.wiley.com/doi/pdf/10.1029/98GL52358
#
# It simulates how a pulse of magma migrates upwards in the Earth, which
# can be described by a set of coupled nonlinear PDE's
#
# This example only requires the specification of a residual routine; automatic
# differentiation is used to generate the jacobian.

using PETSc, MPI

using SparseArrays, SparseDiffTools, ForwardDiff

petsclib = PETSc.petsclibs[1];
PETSc.initialize(petsclib)

CreatePlots = false;
if CreatePlots==true
    using Plots
end


function FormRes!(ptr_fx_g, ptr_x_g, user_ctx)

    # Note that in PETSc, cx and cfx are pointers to global vectors.

    # Copy global to local vectors
    PETSc.update!(user_ctx.x_l, ptr_x_g,   PETSc.INSERT_VALUES)
    PETSc.update!(user_ctx.f_l, ptr_fx_g,  PETSc.INSERT_VALUES)

    # Retrieve arrays from the local vectors
    ArrayLocal_x     =   PETSc.DMStagVecGetArrayRead(user_ctx.dm,   user_ctx.x_l);      # array with all local x-data
    ArrayLocal_f     =   PETSc.DMStagVecGetArray(user_ctx.dm,       user_ctx.f_l);      # array with all local residual

    # Compute local residual
    ComputeLocalResidual(user_ctx.dm, ArrayLocal_x, ArrayLocal_f, user_ctx)

    # Finalize local arrays
    Base.finalize(ArrayLocal_x)
    Base.finalize(ArrayLocal_f)

    # Copy local into global residual vector
    PETSc.update!( ptr_fx_g, user_ctx.f_l, PETSc.INSERT_VALUES)

end

function  ForwardDiff_res(x, user_ctx)
    f   = zero(x)               # vector of zeros, of same type as x (local vector)

    ArrayLocal_x     =   PETSc.DMStagVecGetArray(user_ctx.dm, x);        # array with all local x-data
    ArrayLocal_f     =   PETSc.DMStagVecGetArray(user_ctx.dm, f);        # array with all local residual

    ComputeLocalResidual(user_ctx.dm, ArrayLocal_x, ArrayLocal_f, user_ctx);

    # As the residual vector f is linked with ArrayLocal_f, we don't need to
    # pass ArrayLocal_f back to f

    return f;
end


function  func(out, x, user_ctx)

    ArrayLocal_x     =   PETSc.DMStagVecGetArray(user_ctx.dm, x);        # array with all local x-data
    ArrayLocal_f     =   PETSc.DMStagVecGetArray(user_ctx.dm, out);        # array with all local residual

    ComputeLocalResidual(user_ctx.dm, ArrayLocal_x, ArrayLocal_f, user_ctx);

    return nothing
end



function FormJacobian!(ptr_x_g, J, P, user_ctx)
    # This requires several steps:
    #
    #   1) Extract local vector from global solution (x) vector
    #   2) Compute local jacobian from the residual routine (note that
    #       this routine requires julia vectors as input)

    # Extract the local vector from pointer to global vector
    PETSc.update!(user_ctx.x_l, ptr_x_g, PETSc.INSERT_VALUES)
    x               =   PETSc.unsafe_localarray(Float64, user_ctx.x_l.ptr;  write=false)

    if isnothing(user_ctx.jac)
        # Compute sparsity pattern of jacobian. This is relatvely slow, but only has to be done once.
        # Theoretically, more efficient tools for this exists (jacobian_sparsity in the SparsityDetection.jl package),
        # but they don't seem to work with the PETSc approach we use. Therefore we employ
        f_Residual  =   (x -> ForwardDiff_res(x, user_ctx));        # pass additional arguments into the routine
        J_julia     =   ForwardDiff.jacobian(f_Residual,x);

        # employ sparse structure to compute jacobian - to be moved inside routines
        jac         =   sparse(J_julia);
        colors      =   matrix_colors(jac)          # the number of nonzeros per row

    else
        jac     =   user_ctx.jac;
        colors  =   user_ctx.colors;
    end
    out         =   similar(x);

   f_Res           =   ((out,x)->func(out, x, user_ctx));        # pass additional arguments into the routine
   forwarddiff_color_jacobian!(jac, f_Res, x, colorvec = colors)

    ind             =   PETSc.LocalInGlobalIndices(user_ctx.dm);    # extract indices
    if PETSc.assembled(J) == false
        J           =   PETSc.MatSeqAIJ(sparse(jac[ind,ind]));
    else
        J           .=   sparse(jac[ind,ind]);
    end

    user_ctx.jac    =   jac;
    user_ctx.colors =   colors;

   return jac[ind,ind], ind
end

# Define a struct that holds data we need in the local SNES routines below
mutable struct Data_PorWav1D
    dm
    x_l
    xold_l
    xold_g
    f_l
    dt
    dz
    De
    jac
    colors
end
user_ctx = Data_PorWav1D(nothing, nothing, nothing, nothing, nothing, nothing, nothing, nothing, nothing, nothing);  # holds data we need in the local


function ComputeLocalResidual(dm, ArrayLocal_x, ArrayLocal_f, user_ctx)
    # Compute the local residual. The vectors include ghost points
    n           =   3.0
    m           =   2.0
    dt          =   user_ctx.dt;
    dz          =   user_ctx.dz;
    De          =   user_ctx.De;

    Phi         =   PETSc.DMStagGetGhostArrayLocationSlot(dm,ArrayLocal_x   ,   PETSc.DMSTAG_ELEMENT,   0);
    Phi_old     =   PETSc.DMStagGetGhostArrayLocationSlot(dm,user_ctx.xold_l,   PETSc.DMSTAG_ELEMENT,   0);
    Pe          =   PETSc.DMStagGetGhostArrayLocationSlot(dm,ArrayLocal_x   ,   PETSc.DMSTAG_ELEMENT,   1);
    Pe_old      =   PETSc.DMStagGetGhostArrayLocationSlot(dm,user_ctx.xold_l,   PETSc.DMSTAG_ELEMENT,   1);

    res_Phi     =   PETSc.DMStagGetGhostArrayLocationSlot(dm,ArrayLocal_f,      PETSc.DMSTAG_ELEMENT,   0);
    res_Pe      =   PETSc.DMStagGetGhostArrayLocationSlot(dm,ArrayLocal_f,      PETSc.DMSTAG_ELEMENT,   1);

    # compute the FD stencil
    ind         =     PETSc.DMStagGetIndices(dm);          # indices of (center/element) points, not including ghost values.

    # Porosity residual @ center points
    iz                  =   ind.center[1];                # Phi is on center points
    iz_c                =   iz[2:end-1];                  # central points
    res_Phi[iz[1]]      =   Phi[iz[1]]   - 1.0;           # Bottom BC
    res_Phi[iz[end]]    =   Phi[iz[end]] - 1.0;           # Top BC
    res_Phi[iz_c]       =   (Phi[iz_c] - Phi_old[iz_c])/dt + De.*(Pe[iz_c]-Pe_old[iz_c])/dt + (Phi[iz_c].^m)   .* Pe[iz_c]

    # Pressure update @ center points
    iz                  =   ind.center[1];
    iz_c                =   iz[2:end-1];
    res_Pe[iz[1]]       =   Pe[iz[1]]   - 0.;         # Bottom BC
    res_Pe[iz[end]]     =   Pe[iz[end]] - 0.;         # Top BC
    res_Pe[iz_c]        =   De.*(Pe[iz_c]-Pe_old[iz_c])/dt - ( ((0.5*(Phi[iz_c .+ 1] + Phi[iz_c .+ 0])).^n) .* ( (Pe[iz_c .+ 1] - Pe[iz_c     ])/dz .+ 1.0)  -
                                                               ((0.5*(Phi[iz_c .- 1] + Phi[iz_c .+ 0])).^n) .* ( (Pe[iz_c     ] - Pe[iz_c .- 1])/dz .+ 1.0))/dz  +
                                                                (Phi[iz_c].^m)   .* Pe[iz_c];

    # Cleanup
    Base.finalize(Phi);    Base.finalize(Phi_old);
    Base.finalize(Pe);     Base.finalize(Pe_old);

end


function SetInitialPerturbations(user_ctx, x_g)
    # Computes the initial perturbations as in the paper

    # Retrieve coordinates from DMStag
    DMcoord     =   PETSc.getcoordinateDM(user_ctx.dm)
    vec_coord   =   PETSc.getcoordinateslocal(user_ctx.dm);
    Coord       =   PETSc.DMStagVecGetArray(DMcoord, vec_coord);
    Z_cen       =   PETSc.DMStagGetGhostArrayLocationSlot(user_ctx.dm,Coord, PETSc.DMSTAG_ELEMENT,    0); # center (has 1 extra)
    user_ctx.dz =   Z_cen[2]-Z_cen[1];

    Phi         =   PETSc.DMStagGetGhostArrayLocationSlot(user_ctx.dm,user_ctx.x_l,     PETSc.DMSTAG_ELEMENT, 0);
    Pe          =   PETSc.DMStagGetGhostArrayLocationSlot(user_ctx.dm,user_ctx.x_l,     PETSc.DMSTAG_ELEMENT, 1);
    Phi_old     =   PETSc.DMStagGetGhostArrayLocationSlot(user_ctx.dm,user_ctx.xold_l,  PETSc.DMSTAG_ELEMENT, 0);
    Pe_old      =   PETSc.DMStagGetGhostArrayLocationSlot(user_ctx.dm,user_ctx.xold_l,  PETSc.DMSTAG_ELEMENT, 1);

    Phi0 =1.0; dPhi1=8.0; dPhi2=1.0; z1=0.0; z2=40.0; lambda=1.0
    dPe1        =   dPhi1/user_ctx.De;
    dPe2        =   dPhi2/user_ctx.De;

    Phi        .=   Phi0 .+ dPhi1.*exp.( -((Z_cen .- z1).^2.0)/lambda^2) +  dPhi2.*exp.( -((Z_cen .- z2).^2.0)/lambda^2);
    Pe         .=          -dPe1 .*exp.( -((Z_cen .- z1).^2.0)/lambda^2) -   dPe2.*exp.( -((Z_cen .- z2).^2.0)/lambda^2);

    Phi_old    .=   Phi0 .+ dPhi1.*exp.( -((Z_cen .- z1).^2.0)/lambda^2) +  dPhi2.*exp.( -((Z_cen .- z2).^2.0)/lambda^2);
    Pe_old     .=          -dPe1 .*exp.( -((Z_cen .- z1).^2.0)/lambda^2) -   dPe2.*exp.( -((Z_cen .- z2).^2.0)/lambda^2);

    # Copy local into global residual vector
    #PETSc.DMLocalToGlobal(user_ctx.dm,user_ctx.x_l, PETSc.INSERT_VALUES, x_g)
    PETSc.update!(x_g, user_ctx.x_l, PETSc.INSERT_VALUES);

    # send back coordinates
    return Z_cen
end


# Main Solver
nx              =   1001;
L               =   150;
#user_ctx.De     =   1e-2;        # Deborah number
#user_ctx.dt     =   5e-5;        # Note that the timestep has to be tuned a bit depending on De in order to obtain convergence
user_ctx.De     =   1e2;
user_ctx.dt     =   1e-2;        # Note that the timestep has to be tuned a bit depending on De in order to obtain convergence

user_ctx.dm     =   PETSc.DMStagCreate1d(petsclib, MPI.COMM_WORLD,PETSc.DM_BOUNDARY_NONE,nx,0,2);  # both Phi and Pe are on center points
PETSc.DMStagSetUniformCoordinatesExplicit(user_ctx.dm, -20, L)            # set coordinates
x_g             =   PETSc.createglobalvector(user_ctx.dm)


f_g             =   PETSc.createglobalvector(user_ctx.dm)
user_ctx.x_l    =   PETSc.createlocalvector(user_ctx.dm)
user_ctx.xold_l =   PETSc.createlocalvector(user_ctx.dm)
user_ctx.xold_g =   PETSc.createglobalvector(user_ctx.dm)
user_ctx.f_l    =   PETSc.createlocalvector(user_ctx.dm)
J               =   PETSc.creatematrix(user_ctx.dm);                  # Jacobian from DMStag


# initial non-zero structure of jacobian
Z_cen           =   SetInitialPerturbations(user_ctx, x_g)

x0              =   PETSc.createglobalvector(user_ctx.dm);
x0[1:length(x0)] .= 1
J_julia,ind     =   FormJacobian!(x0, J, J, user_ctx)
J               =      PETSc.MatSeqAIJ(J_julia)


S = PETSc.SNES{Float64}(petsclib, MPI.COMM_SELF;
        snes_rtol=1e-12,
        snes_monitor=true,
        snes_max_it = 500,
        snes_monitor_true_residual=true,
        snes_converged_reason=true);
S.user_ctx  =       user_ctx;


SetInitialPerturbations(user_ctx, x_g)

PETSc.setfunction!(S, FormRes!, f_g)
PETSc.setjacobian!(S, FormJacobian!, J, J)

# Preparation of visualisation
if CreatePlots
    ENV["GKSwstype"]="nul";
    if isdir("viz_out")==true
        rm("viz_out", recursive=true)
    end
    mkdir("viz_out")
    loadpath = "./viz_out/"; anim = Animation(loadpath,String[])
end


time = 0.0;
it   = 1;
while time<2.5
    global time, Z, Z_cen, it

    # Solve one (nonlinear) timestep
    PETSc.solve!(x_g, S);

    # Update old local values
    user_ctx.xold_g  =  x_g;
    PETSc.update!(user_ctx.x_l, x_g,  PETSc.INSERT_VALUES,  )
    PETSc.update!(user_ctx.xold_l, user_ctx.xold_g,  PETSc.INSERT_VALUES,  )

    # Update time
    time += user_ctx.dt;
    it   += 1;

    if (mod(it,20)==0) & (CreatePlots==true) # Visualisation
        # Extract values and plot
        Phi         =   PETSc.DMStagGetGhostArrayLocationSlot(user_ctx.dm,user_ctx.x_l,     PETSc.DMSTAG_ELEMENT, 0);
        Pe          =   PETSc.DMStagGetGhostArrayLocationSlot(user_ctx.dm,user_ctx.x_l,     PETSc.DMSTAG_ELEMENT, 1);

        p1 = plot(Phi[1:end-1], Z_cen[1:end-1],  ylabel="Z", xlabel="ϕ",  xlims=( 0.0, 2.0), label=:none, title="De=$(user_ctx.De)");
        #p2 = plot(Pe[1:end-1],  Z_cen[1:end-1]    ,                       xlabel="Pe", xlims=(-1.25, 1.25), label=:none, title="$(round(time;sigdigits=3))");
        p2 = plot(Pe[1:end-1],  Z_cen[1:end-1]    ,                       xlabel="Pe", xlims=(-0.025, 0.01), label=:none, title="$(round(time;sigdigits=3))");

       # p1 = plot(Phi[1:end-1], Z_cen[1:end-1],  ylabel="Z", xlabel="ϕ",   label=:none, title="De=$(user_ctx.De)");
       # p2 = plot(Pe[1:end-1],  Z_cen[1:end-1]    ,                       xlabel="Pe",  label=:none, title="$(round(time;sigdigits=3))");

        plot(p1, p2, layout=(1,2)); frame(anim)

        Base.finalize(Pe);  Base.finalize(Phi)
    end

    println("Timestep $it, time=$time")

end

if CreatePlots==true
    gif(anim, "Example_1D.gif", fps = 15)   # create a gif animation
end
