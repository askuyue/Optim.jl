typealias FirstOrderSolver Union{AcceleratedGradientDescent, ConjugateGradient, GradientDescent,
                                 MomentumGradientDescent, BFGS, LBFGS}
typealias SecondOrderSolver Union{Newton, NewtonTrustRegion}
# Multivariate optimization
function check_kwargs(kwargs, fallback_method)
    kws = Dict{Symbol, Any}()
    method = nothing
    for kwarg in kwargs
        if kwarg[1] != :method
            kws[kwarg[1]] = kwarg[2]
        else
            method = kwarg[2]
        end
    end

    if method == nothing
        method = fallback_method
    end
    kws, method
end

function optimize{F<:Function}(f::F, initial_x::Array; kwargs...)
    checked_kwargs, method = check_kwargs(kwargs, NelderMead())
    optimize(f, initial_x, method, Options(; checked_kwargs...))
end

function optimize{F<:Function, G<:Function}(f::F, g!::G, initial_x::Array; kwargs...)
    checked_kwargs, method = check_kwargs(kwargs, BFGS())
    optimize(f, g!, initial_x, method, Options(;checked_kwargs...))
end
function optimize(d::DifferentiableFunction, initial_x::Array; kwargs...)
    checked_kwargs, method = check_kwargs(kwargs, BFGS())
    optimize(d, initial_x, method, Options(checked_kwargs...))
end

function optimize{F<:Function, G<:Function, H<:Function}(f::F,
                  g!::G,
                  h!::H,
                  initial_x::Array; kwargs...)
    checked_kwargs, method = check_kwargs(kwargs, Newton())
    optimize(f, g!, h!, initial_x, method, Options(checked_kwargs...))
end

function optimize(d::TwiceDifferentiableFunction, initial_x::Array; kwargs...)
    checked_kwargs, method = check_kwargs(kwargs, Newton())
    optimize(d, initial_x, method, Options(;kwargs...))
end


function optimize(d, initial_x::Array,
                  method::Optimizer, options::Options = Options())
    optimize(d, initial_x, method, options)
end
optimize(d::Function, initial_x, options::Options) = optimize(d, initial_x, NelderMead(), options)
optimize(d::DifferentiableFunction, initial_x, options::Options) = optimize(d, initial_x, BFGS(), options)
optimize(d::TwiceDifferentiableFunction, initial_x, options::Options) = optimize(d, initial_x, Newton(), options)

function optimize{F<:Function, G<:Function}(f::F,
                  g!::G,
                  initial_x::Array,
                  method::Optimizer,
                  options::Options = Options())
    d = DifferentiableFunction(f, g!, initial_x)
    optimize(d, initial_x, method, options)
end
function optimize{F<:Function, G<:Function}(f::F,
                  g!::G,
                  initial_x::Array,
                  options::Options)
    d = DifferentiableFunction(f, g!, initial_x)
    optimize(d, initial_x, BFGS(), options)
end

function optimize{F<:Function, G<:Function, H<:Function}(f::F,
                  g!::G,
                  h!::H,
                  initial_x::Array,
                  method::Optimizer,
                  options::Options = Options())
    d = TwiceDifferentiableFunction(f, g!, h!, initial_x)
    optimize(d, initial_x, method, options)
end
function optimize{F<:Function, G<:Function, H<:Function}(f::F,
                  g!::G,
                  h!::H,
                  initial_x::Array,
                  options)
    d = TwiceDifferentiableFunction(f, g!, h!, initial_x)
    optimize(d, initial_x, Newton(), options)
end

function optimize{F<:Function, T, M <: Union{FirstOrderSolver, SecondOrderSolver}}(f::F,
                  initial_x::Array{T},
                  method::M,
                  options::Options)
    if !options.autodiff
        if M <: FirstOrderSolver
            d = DifferentiableFunction(f, initial_x)
        else
            error("No gradient or Hessian was provided. Either provide a gradient and Hessian, set autodiff = true in the Options if applicable, or choose a solver that doesn't require a Hessian.")
        end
    else
        gcfg = ForwardDiff.GradientConfig(initial_x)
        g! = (x, out) -> ForwardDiff.gradient!(out, f, x, gcfg)

        fg! = (x, out) -> begin
            gr_res = DiffBase.DiffResult(zero(T), out)
            ForwardDiff.gradient!(gr_res, f, x, gcfg)
            DiffBase.value(gr_res)
        end

        if M <: FirstOrderSolver
            d = DifferentiableFunction(f, g!, fg!, initial_x)
        else
            hcfg = ForwardDiff.HessianConfig(initial_x)
            h! = (x, out) -> ForwardDiff.hessian!(out, f, x, hcfg)
            d = TwiceDifferentiableFunction(f, g!, fg!, h!, initial_x)
        end
    end

    optimize(d, initial_x, method, options)
end

function optimize(d::DifferentiableFunction,
                  initial_x::Array,
                  method::Newton,
                  options::Options)
    if !options.autodiff
        throw(ArgumentError("No Hessian was provided. Either provide a Hessian, set autodiff = true in the Options if applicable, or choose a solver that doesn't require a Hessian."))
    else
        hcfg = ForwardDiff.HessianConfig(initial_x)
        h! = (x, out) -> ForwardDiff.hessian!(out, d.f, x, hcfg)
    end
    optimize(TwiceDifferentiableFunction(d.f, d.g!, d.fg!, h!, initial_x), initial_x, method, options)
end

function optimize(d::DifferentiableFunction,
                  initial_x::Array,
                  method::NewtonTrustRegion,
                  options::Options)
    if !options.autodiff
        throw(ArgumentError("No Hessian was provided. Either provide a Hessian, set autodiff = true in the Options if applicable, or choose a solver that doesn't require a Hessian."))
    else
        hcfg = ForwardDiff.HessianConfig(initial_x)
        h! = (x, out) -> ForwardDiff.hessian!(out, d.f, x, hcfg)
    end
    optimize(TwiceDifferentiableFunction(d.f, d.g!, d.fg!, h!, initial_x), initial_x, method, options)
end

update_g!(d, state, method) = nothing

function update_g!{M<:Union{FirstOrderSolver, Newton}}(d, state, method::M)
    # Update the function value and gradient
    state.f_x_previous, d.f_x = d.f_x, value_grad!(d,state.x)
end

update_h!(d, state, method) = nothing

# Update the Hessian
function update_h!(d, state, method::SecondOrderSolver)
    d.h!(state.x, state.H)
end

function clear_object!(d::NonDifferentiableFunction)
    d.f_calls = 0
end
function clear_object!(d::DifferentiableFunction)
    d.f_calls = 0
    d.g_calls = 0
end
function clear_object!(d::TwiceDifferentiableFunction)
    d.f_calls = 0
    d.g_calls = 0
    d.h_calls = 0
end

after_while!(d, state, method, options) = nothing
optimize{T, M<:Union{SimulatedAnnealing, NelderMead, ParticleSwarm}}(d::Function, initial_x::Array{T}, method::M, options::Options)=
optimize(NonDifferentiableFunction(d, initial_x), initial_x, method, options)
function optimize{T, M<:Optimizer}(d, initial_x::Array{T}, method::M, options::Options)
    t0 = time() # Initial time stamp used to control early stopping by options.time_limit
    clear_object!(d)

    if length(initial_x) == 1 && typeof(method) <: NelderMead
        error("Use optimize(f, scalar, scalar) for 1D problems")
    end


    state = initial_state(method, options, d, initial_x)

    tr = OptimizationTrace{typeof(method)}()
    tracing = options.store_trace || options.show_trace || options.extended_trace || options.callback != nothing
    stopped, stopped_by_callback, stopped_by_time_limit = false, false, false

    x_converged, f_converged = false, false
    g_converged = if typeof(method) <: NelderMead
        nmobjective(state.f_simplex, state.m, state.n) < options.g_tol
    elseif  typeof(method) <: ParticleSwarm || typeof(method) <: SimulatedAnnealing
        g_converged = false
    else
        vecnorm(grad(d), Inf) < options.g_tol
    end

    converged = g_converged
    iteration = 0

    options.show_trace && print_header(method)
    trace!(tr, d, state, iteration, method, options)

    while !converged && !stopped && iteration < options.iterations
        iteration += 1

        update_state!(d, state, method) && break # it returns true if it's forced by something in update! to stop (eg dx_dg == 0.0 in BFGS)
        update_g!(d, state, method)
        x_converged, f_converged,
        g_converged, converged = assess_convergence(d, state, options)
        # We don't use the Hessian for anything if we have declared convergence,
        # so we might as well not make the (expensive) update if converged == true
        !converged && update_h!(d, state, method)

        # If tracing, update trace with trace!. If a callback is provided, it
        # should have boolean return value that controls the variable stopped_by_callback.
        # This allows for early stopping controlled by the callback.
        if tracing
            stopped_by_callback = trace!(tr, d, state, iteration, method, options)
        end

        # Check time_limit; if none is provided it is NaN and the comparison
        # will always return false.
        stopped_by_time_limit = time()-t0 > options.time_limit ? true : false

        # Combine the two, so see if the stopped flag should be changed to true
        # and stop the while loop
        stopped = stopped_by_callback || stopped_by_time_limit ? true : false
    end # while

    after_while!(d, state, method, options)
    return MultivariateOptimizationResults(state.method_string,
                                            initial_x,
                                            state.x,
                                            Float64(d.f_x),
                                            iteration,
                                            iteration == options.iterations,
                                            x_converged,
                                            options.x_tol,
                                            f_converged,
                                            options.f_tol,
                                            g_converged,
                                            options.g_tol,
                                            tr,
                                            f_calls(d),
                                            g_calls(d),
                                            h_calls(d))
end

# Univariate Options
function optimize{F<:Function, T <: AbstractFloat}(f::F,
                                      lower::T,
                                      upper::T;
                                      method = Brent(),
                                      rel_tol::Real = sqrt(eps(T)),
                                      abs_tol::Real = eps(T),
                                      iterations::Integer = 1_000,
                                      store_trace::Bool = false,
                                      show_trace::Bool = false,
                                      callback = nothing,
                                      show_every = 1,
                                      extended_trace::Bool = false)
    show_every = show_every > 0 ? show_every: 1
    if extended_trace && callback == nothing
        show_trace = true
    end
    if show_trace
        @printf "Iter     Function value   Gradient norm \n"
    end
    optimize(f, lower, upper, method;
             rel_tol = T(rel_tol),
             abs_tol = T(abs_tol),
             iterations = iterations,
             store_trace = store_trace,
             show_trace = show_trace,
             show_every = show_every,
             callback = callback,
             extended_trace = extended_trace)
end

function optimize{F<:Function}(f::F,
                  lower::Real,
                  upper::Real;
                  kwargs...)
    optimize(f,
             Float64(lower),
             Float64(upper);
             kwargs...)
end

function optimize{F<:Function}(f::F,
                  lower::Real,
                  upper::Real,
                  mo::Union{Brent, GoldenSection};
                  kwargs...)
    optimize(f,
             Float64(lower),
             Float64(upper),
             mo;
             kwargs...)
end
