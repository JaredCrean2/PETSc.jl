# PETSc

[![Build Status](https://github.com/JuliaParallel/PETSc.jl/workflows/CI/badge.svg)](https://github.com/JuliaParallel/PETSc.jl/actions/workflows/ci.yml)

This package provides a low level interface for
[PETSc](https://www.mcs.anl.gov/petsc/)

## Installation

This package can be added with the julia command:
```julia
]add https://github.com/JuliaParallel/PETSc.jl
```
The installation can be tested with
```julia
]test PETSc
```

## BinaryBuilder Version

By default, the package uses a pre-build binary of
[`PETSc`](https://github.com/JuliaBinaryWrappers/PETSc_jll.jl) along with a
default installation of `MPI.jl`. Note that the distributed version of PETSc is using real,
`Float64` numbers; build details can be found
[here](https://github.com/JuliaPackaging/Yggdrasil/blob/master/P/PETSc/build_tarballs.jl)

## System Builds

If you want to use the package with custom builds of the PETSc library, this can
be done by specifying the environment variable `JULIA_PETSC_LIBRARY`. This is a
colon separated list of paths to custom builds of PETSc; the reason for using
multiple builds is to enable single, double, and complex numbers in the same
julia session. These should be built against the same version of MPI as used
with `MPI.jl`

After setting the variable you should
```julia
]build PETSc
```
and the library will be persistently set until the next time the build command
is issued.

To see the currently set library use
```julia
using PETSc
PETSc.libs
```
