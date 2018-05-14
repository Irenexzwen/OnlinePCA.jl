"""
    svrg(;input::AbstractString="", outdir::Union{Void,AbstractString}=nothing, logscale::Bool=true, pseudocount::Number=1.0, rowmeanlist::AbstractString="", colsumlist::AbstractString="", masklist::AbstractString="", dim::Number=3, stepsize::Number=0.1, numepoch::Number=5, scheduling::AbstractString="robbins-monro", g::Number=0.9, epsilon::Number=1.0e-8, logdir::Union{Void,AbstractString}=nothing)

Online PCA solved by variance-reduced stochastic gradient descent method, also known as VR-PCA.

Input Arguments
---------
- `input` : Julia Binary file generated by `OnlinePCA.csv2bin` function.
- `outdir` : The directory specified the directory you want to save the result.
- `logscale`  : Whether the count value is converted to log10(x + pseudocount).
- `pseudocount` : The number specified to avoid NaN by log10(0) and used when `Feature_LogMeans.csv` <log10(mean+pseudocount) value of each feature> is generated.
- `rowmeanlist` : The mean of each row of matrix. The CSV file is generated by `OnlinePCA.sumr` functions.
- `colsumlist` : The sum of counts of each columns of matrix. The CSV file is generated by `OnlinePCA.sumr` functions.
- `masklist` : The column list that user actually analyze.
- `dim` : The number of dimension of PCA.
- `stepsize` : The parameter used in every iteration.
- `numepoch` : The number of epoch.
- `scheduling` : Learning parameter scheduling. `robbins-monro`, `momentum`, `nag`, and `adagrad` are available.
- `g` : The parameter that is used when scheduling is specified as nag.
- `epsilon` : The parameter that is used when scheduling is specified as adagrad.
- `logdir` : The directory where intermediate files are saved, in every 1000 iteration.

Output Arguments
---------
- `W` : Eigen vectors of covariance matrix (No. columns of the data matrix × dim)
- `λ` : Eigen values (dim × dim)
- `V` : Loading vectors of covariance matrix (No. rows of the data matrix × dim)

Reference
---------
- SVRG-PCA : [Ohad Shamir, 2015](http://proceedings.mlr.press/v37/shamir15.pdf)
"""
function svrg(;input::AbstractString="", outdir::Union{Void,AbstractString}=nothing, logscale::Bool=true, pseudocount::Number=1.0, rowmeanlist::AbstractString="", colsumlist::AbstractString="", masklist::AbstractString="", dim::Number=3, stepsize::Number=0.1, numepoch::Number=5, scheduling::AbstractString="robbins-monro", g::Number=0.9, epsilon::Number=1.0e-8, logdir::Union{Void,AbstractString}=nothing)
    # Initial Setting
    pca = SVRG()
    if scheduling == "robbins-monro"
        scheduling = ROBBINS_MONRO()
    elseif scheduling == "momentum"
        scheduling = MOMENTUM()
    elseif scheduling == "nag"
        scheduling = NAG()
    elseif scheduling == "adagrad"
        scheduling = ADAGRAD()
    else
        error("Specify the scheduling as robbins-monro, momentum, nag or adagrad")
    end
    pseudocount, stepsize, g, epsilon, W, v, D, rowmeanvec, colsumvec, maskvec, N, M, AllVar = init(input, pseudocount, stepsize, g, epsilon, dim, rowmeanlist, colsumlist, masklist, logdir, pca, logscale)
    # Perform PCA
    out = svrg(input, outdir, logscale, pseudocount, rowmeanlist, colsumlist, masklist, dim, stepsize, numepoch, scheduling, g, epsilon, logdir, pca, W, v, D, rowmeanvec, colsumvec, maskvec, N, M, AllVar)
    if typeof(outdir) == String
        output(outdir, out)
    end
    return out
end

function svrg(input, outdir, logscale, pseudocount, rowmeanlist, colsumlist, masklist, dim, stepsize, numepoch, scheduling, g, epsilon, logdir, pca, W, v, D, rowmeanvec, colsumvec, maskvec, N, M, AllVar)
    N, M = nm(input)
    tmpN = zeros(UInt32, 1)
    tmpM = zeros(UInt32, 1)
    x = zeros(UInt32, M)
    normx = zeros(Float32, M)
    # Each epoch s
    progress = Progress(numepoch)
    for s = 1:numepoch
        u = ∇f(W, input, D, logscale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, colsumlist, colsumvec, stepsize/s)
        Ws = W
        open(input) do file
            stream = LZ4DecompressorStream(file)
            read!(stream, tmpN)
            read!(stream, tmpM)
            # Each step n
            for n = 1:N
                # Row vector of data matrix
                read!(stream, x)
                normx = normalizex(x, n, stream, logscale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, colsumlist, colsumvec)
                # Update Eigen vector
                W, v = svrgupdate(scheduling, stepsize, g, epsilon, D, N, M, W, v, normx, s, n, u, Ws)
                # NaN
                checkNaN(N, s, n, W, pca)
                # Retraction
                W .= full(qrfact!(W)[:Q], thin=true)
                # save log file
                if typeof(logdir) == String
                    outputlog(N, s, n, input, logdir, W, pca, AllVar, logscale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, colsumlist, colsumvec)
                end
            end
            close(stream)
        end
        next!(progress)
    end

    # Return, W, λ, V
    WλV(W, input, dim)
end

# SVRG × Robbins-Monro
function svrgupdate(scheduling::ROBBINS_MONRO, stepsize, g, epsilon, D, N, M, W, v, normx, s, n, u, Ws)
    W .= W .+ Pw(∇fn(W, normx, D, M, stepsize/(N*(s-1)+n)), W) .- Pw(∇fn(Ws, normx, D, M, stepsize/(N*(s-1)+n)), Ws) .+ u
    v = nothing
    return W, v
end

# SVRG × Momentum
function svrgupdate(scheduling::MOMENTUM, stepsize, g, epsilon, D, N, M, W, v, normx, s, n, u, Ws)
    v .= g .* v .+ ∇fn(W, normx, D, M, stepsize) .- ∇fn(Ws, normx, D, M, stepsize) .+ u
    W .= W .+ v
    return W, v
end

# SVRG × NAG
function svrgupdate(scheduling::NAG, stepsize, g, epsilon, D, N, M, W, v, normx, s, n, u, Ws)
    v = g .* v + ∇fn(W - g .* v, normx, D, M, stepsize) .- ∇fn(Ws, normx, D, M, stepsize) .+ u
    W .= W .+ v
    return W, v
end

# SVRG × Adagrad
function svrgupdate(scheduling::ADAGRAD, stepsize, g, epsilon, D, N, M, W, v, normx, s, n, u, Ws)
    grad = ∇fn(W, normx, D, M, stepsize) .- ∇fn(Ws, normx, D, M, stepsize) .+ u
    grad = grad / stepsize
    v .= v .+ grad .* grad
    W .= W .+ stepsize ./ (sqrt.(v) + epsilon) .* grad
    return W, v
end
