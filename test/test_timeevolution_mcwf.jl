using Base.Test
using quantumoptics

# Define parameters for spin coupled to electric field mode.
ωc = 1.2
ωa = 0.9
g = 1.0
γ = 0.5
κ = 1.1

Ntrajectories = 500
T = Float64[0.:0.1:10.;]

# Define operators
fockbasis = FockBasis(8)
spinbasis = SpinBasis(1//2)
basis = tensor(spinbasis, fockbasis)

sx = sigmax(spinbasis)
sy = sigmay(spinbasis)
sz = sigmaz(spinbasis)
sp = sigmap(spinbasis)
sm = sigmam(spinbasis)

# Hamiltonian
Ha = embed(basis, 1, 0.5*ωa*sz)
Hc = embed(basis, 2, ωc*number(fockbasis))
Hint = sm ⊗ create(fockbasis) + sp ⊗ destroy(fockbasis)
H = Ha + Hc + Hint
Hsparse = SparseOperator(H)

# Jump operators
Ja = embed(basis, 1, sqrt(γ)*sm)
Jc = embed(basis, 2, sqrt(κ)*destroy(fockbasis))
J = [Ja, Jc]
Jsparse = map(SparseOperator, J)

# Initial conditions
Ψ₀ = spinup(spinbasis) ⊗ fockstate(fockbasis, 5)
ρ₀ = Ψ₀ ⊗ dagger(Ψ₀)


# Test mcwf
tout, Ψt = timeevolution.mcwf(T, Ψ₀, H, J; seed=UInt64(1), reltol=1e-7)
Ψ = Ψt[end]

tout, Ψt = timeevolution.mcwf(T, Ψ₀, Hsparse, Jsparse; seed=UInt64(1), reltol=1e-6)
@test norm(Ψt[end]-Ψ) < 1e-5

tout, Ψt = timeevolution.mcwf(T, Ψ₀, Hsparse, Jsparse; seed=UInt64(2), reltol=1e-6)
@test norm(Ψt[end]-Ψ) > 0.1


# Test mcwf_h
tout, Ψt = timeevolution.mcwf_h(T, Ψ₀, Hsparse, Jsparse; seed=UInt64(1), reltol=1e-6)
@test norm(Ψt[end]-Ψ) < 1e-5

tout, Ψt = timeevolution.mcwf_h(T, Ψ₀, Hsparse, J; seed=UInt64(1), reltol=1e-6)
@test norm(Ψt[end]-Ψ) < 1e-5

tout, Ψt = timeevolution.mcwf_h(T, Ψ₀, H, Jsparse; seed=UInt64(1), reltol=1e-6)
@test norm(Ψt[end]-Ψ) < 1e-5

tout, Ψt = timeevolution.mcwf_h(T, Ψ₀, Hsparse, Jsparse; seed=UInt64(2), reltol=1e-6)
@test norm(Ψt[end]-Ψ) > 0.1


# Test mcwf nh
Hnh = H - 0.5im*sum([dagger(J[i])*J[i] for i=1:length(J)])
Hnh_sparse = SparseOperator(Hnh)

tout, Ψt = timeevolution.mcwf_nh(T, Ψ₀, Hnh_sparse, Jsparse; seed=UInt64(1), reltol=1e-6)
@test norm(Ψt[end]-Ψ) < 1e-5

tout, Ψt = timeevolution.mcwf_nh(T, Ψ₀, Hnh_sparse, J; seed=UInt64(1), reltol=1e-6)
@test norm(Ψt[end]-Ψ) < 1e-5

tout, Ψt = timeevolution.mcwf_nh(T, Ψ₀, Hnh, Jsparse; seed=UInt64(1), reltol=1e-6)
@test norm(Ψt[end]-Ψ) < 1e-5

tout, Ψt = timeevolution.mcwf_nh(T, Ψ₀, Hnh_sparse, Jsparse; seed=UInt64(2), reltol=1e-6)
@test norm(Ψt[end]-Ψ) > 0.1



# Test convergence to master solution
tout_master, ρt_master = timeevolution.master(T, ρ₀, H, J)

ρ_average = DenseOperator[0 * ρ₀ for i=1:length(T)]
for i=1:Ntrajectories
    tout, Ψt = timeevolution.mcwf(T, Ψ₀, H, J; seed=UInt64(i))
    for j=1:length(T)
        ρ_average[j] += (Ψt[j] ⊗ dagger(Ψt[j]))/Ntrajectories
    end
end
for i=1:length(T)
    err = quantumoptics.tracedistance(ρt_master[i], ρ_average[i])
    @test err < 0.1
end


# Test single jump operator
J1 = [Ja]
J2 = [Ja, 0 * Jc]

tout_master, ρt_master = timeevolution.master(T, ρ₀, H, J1)

ρ_average_1 = DenseOperator[0 * ρ₀ for i=1:length(T)]
ρ_average_2 = DenseOperator[0 * ρ₀ for i=1:length(T)]
for i=1:Ntrajectories
    tout, Ψt_1 = timeevolution.mcwf(T, Ψ₀, H, J1; seed=UInt64(i))
    tout, Ψt_2 = timeevolution.mcwf(T, Ψ₀, H, J2; seed=UInt64(i))
    for j=1:length(T)
        ρ_average_1[j] += (Ψt_1[j] ⊗ dagger(Ψt_1[j]))/Ntrajectories
        ρ_average_2[j] += (Ψt_2[j] ⊗ dagger(Ψt_2[j]))/Ntrajectories
    end
end
for i=1:length(T)
    @test quantumoptics.tracedistance(ρt_master[i], ρ_average_1[i]) < 0.1
    @test quantumoptics.tracedistance(ρt_master[i], ρ_average_2[i]) < 0.1
end


# Test equivalence to schroedinger time evolution for no decay
J = DenseOperator[]
tout_schroedinger, Ψt_schroedinger = timeevolution.schroedinger(T, Ψ₀, H)
tout_mcwf, Ψt_mcwf = timeevolution.mcwf(T, Ψ₀, H, J)
tout_mcwf_h, Ψt_mcwf_h = timeevolution.mcwf_h(T, Ψ₀, H, J)
tout_mcwf_nh, Ψt_mcwf_nh = timeevolution.mcwf_nh(T, Ψ₀, H, J)

for i=1:length(T)
    @test norm(Ψt_mcwf[i] - Ψt_schroedinger[i]) < 1e-4
    @test norm(Ψt_mcwf_h[i] - Ψt_schroedinger[i]) < 1e-4
    @test norm(Ψt_mcwf_nh[i] - Ψt_schroedinger[i]) < 1e-4
end
