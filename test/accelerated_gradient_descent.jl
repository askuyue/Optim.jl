# TODO expand tests here
let
    f(x) = x[1]^4
    function g!(x, storage)
        storage[1] = 4 * x[1]^3
        return
    end

    initial_x = [1.0]
    d = DifferentiableFunction(f, g!, initial_x)
    options = Optim.Options(show_trace = true, iterations = 10)
    Optim.optimize(d, initial_x, AcceleratedGradientDescent(), options)
end
