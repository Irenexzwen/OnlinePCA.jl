"""
    tenxpca(;tenxfile::AbstractString="", outdir::Union{Nothing,AbstractString}=nothing, scale::AbstractString="sqrt", rowmeanlist::AbstractString="", rowvarlist::AbstractString="", colsumlist::AbstractString="", dim::Number=3, noversamples::Number=5, niter::Number=3, chunksize::Number=5000, group::AbstractString, initW::Union{Nothing,AbstractString}=nothing, initV::Union{Nothing,AbstractString}=nothing, logdir::Union{Nothing,AbstractString}=nothing, perm::Bool=false)

A randomized SVD.

Input Arguments
---------
- `tenxfile` : Julia Binary file generated by `OnlinePCA.csv2bin` function.
- `outdir` : The directory specified the directory you want to save the result.
- `scale` : {sqrt,log,raw}-scaling of the value.
- `rowmeanlist` : The mean of each row of matrix. The CSV file is generated by `OnlinePCA.sumr` functions.
- `rowvarlist` : The variance of each row of matrix. The CSV file is generated by `OnlinePCA.sumr` functions.
- `colsumlist` : The sum of counts of each columns of matrix. The CSV file is generated by `OnlinePCA.sumr` functions.
- `dim` : The number of dimension of PCA.
- `noversamples` : The number of over-sampling.
- `niter` : The number of power interation.
- `chunksize` is the number of rows reading at once (e.g. 5000).
- `group` : The group name of 10XHDF5 (e.g. mm10).
- `initW` : The CSV file saving the initial values of eigenvectors.
- `initV` : The CSV file saving the initial values of loadings.
- `logdir` : The directory where intermediate files are saved, in every evalfreq (e.g. 5000) iteration.
- `perm` : Whether the data matrix is shuffled at random.

Output Arguments
---------
- `V` : Eigen vectors of covariance matrix (No. columns of the data matrix × dim)
- `λ` : Eigen values (dim × dim)
- `U` : Loading vectors of covariance matrix (No. rows of the data matrix × dim)
- `Scores` : Principal component scores
- `ExpVar` : Explained variance by the eigenvectors
- `TotalVar` : Total variance of the data matrix
"""

# Total Variance
function tv(TotalVar::Number, X::AbstractArray)
    l = size(X)[2]
    progress = Progress(l)
    for i in 1:l
        TotalVar = TotalVar + X[:,i]'*X[:,i]
        # Progress Bar
        next!(progress)
    end
    TotalVar
end

# Normalization of X
function tenxnormalizex(X, scale)
    if scale == "sqrt"
        X = sqrt.(X)
    end
    if scale == "log"
        X = log10.(X .+ 1)
    end
    return X
end

# Initialization (only TENXPCA)
function tenxinit(tenxfile::AbstractString, dim::Number, chunksize::Number, group::AbstractString, rowmeanlist::AbstractString, rowvarlist::AbstractString, colsumlist::AbstractString, initW::Union{Nothing,AbstractString}, initV::Union{Nothing,AbstractString}, logdir::Union{Nothing,AbstractString}, pca::TENXPCA, scale::AbstractString="sqrt", perm::Bool=false)
    N, M = tenxnm(tenxfile, group)
    # Eigen vectors
    if initW == nothing
        W = zeros(Float32, M, dim)
        for i=1:dim
            W[i, i] = 1
        end
    end
    if typeof(initW) == String
        if initV == nothing
            W = readcsv(initW, Float32)
        else
            error("initW and initV are not specified at once. You only have one choice.")
        end
    end
    if typeof(initV) == String
            V = readcsv(initV, Float32)
            V = V[:,1:dim]
    end
    D = Diagonal(reverse(1:dim)) # Diagonal Matrix
    rowmeanvec = zeros(Float32, N, 1)
    rowvarvec = zeros(Float32, N, 1)
    colsumvec = zeros(Float32, M, 1)
    if rowmeanlist != ""
        rowmeanvec = readcsv(rowmeanlist, Float32)
    end
    if rowvarlist != ""
        rowvarvec = readcsv(rowvarlist, Float32)
    end
    if colsumlist != ""
        colsumvec = readcsv(colsumlist, Float32)
    end
    # N, M, All Variance
    TotalVar = 0.0
    # Index Pointer
    idp = indptr(tenxfile, group)
    # Each chunk
    if N > chunksize
        lasti = fld(N, chunksize)+1
    else
        lasti = 1
    end
    for i in 1:lasti
        startp = Int64((i-1)*chunksize+1)
        endp = Int64(i*chunksize)
        if N - endp + chunksize < chunksize
            endp = N
        end
        println("Loading a chunk of sparse matrix from 10XHDF5...")
        X = loadchromium(tenxfile, group, idp, startp, endp, M, perm)
        X = tenxnormalizex(X, scale)
        println("Calculating the total variance...")
        TotalVar = tv(TotalVar, X)
        # Creating W from V
        if typeof(initV) == String
            W = W .+ (V[n,:]*X')'
        end
    end
    TotalVar = TotalVar / M
    # directory for log file
    if logdir isa String
        if(!isdir(logdir))
            mkdir(logdir)
        end
    end
    return W, D, rowmeanvec, rowvarvec, colsumvec, N, M, TotalVar, idp
end

function tenxpca(;tenxfile::AbstractString="", outdir::Union{Nothing,AbstractString}=nothing, scale::AbstractString="sqrt", rowmeanlist::AbstractString="", rowvarlist::AbstractString="", colsumlist::AbstractString="", dim::Number=3, noversamples::Number=5, niter::Number=3, chunksize::Number=5000, group::AbstractString, initW::Union{Nothing,AbstractString}=nothing, initV::Union{Nothing,AbstractString}=nothing, logdir::Union{Nothing,AbstractString}=nothing, perm::Bool=false)
    # Initial Setting
    # Input
    if !(scale in ["sqrt", "log", "raw"])
        error("scale must be specified as sqrt, log, or raw")
    end
    pca = TENXPCA()
    println("Initial Setting...")
    W, D, rowmeanvec, rowvarvec, colsumvec, N, M, TotalVar, idp = tenxinit(tenxfile, dim, chunksize, group, rowmeanlist, rowvarlist, colsumlist, initW, initV, logdir, pca, scale, perm)
    # Perform PCA
    out = tenxpca(tenxfile, outdir, scale, rowmeanlist, rowvarlist, colsumlist, dim, noversamples, niter, chunksize, logdir, pca, W, D, rowmeanvec, rowvarvec, colsumvec, N, M, TotalVar, perm, idp, group)
    # Output
    if outdir isa String
        writecsv(joinpath(outdir, "Eigen_vectors.csv"), out[1])
        writecsv(joinpath(outdir, "Eigen_values.csv"), out[2])
        writecsv(joinpath(outdir, "Loadings.csv"), out[3])
        writecsv(joinpath(outdir, "Scores.csv"), out[4])
        writecsv(joinpath(outdir, "ExpVar.csv"), out[5])
        writecsv(joinpath(outdir, "TotalVar.csv"), out[6])
    end
    return out
end

function tenxpca(tenxfile, outdir, scale, rowmeanlist, rowvarlist, colsumlist, dim, noversamples, niter, chunksize, logdir, pca, W, D, rowmeanvec, rowvarvec, colsumvec, N, M, TotalVar, perm, idp, group)
    # Setting
    N, M = tenxnm(tenxfile, group)
    l = dim + noversamples
    @assert 0 < dim ≤ l ≤ min(N, M)
    Ω = rand(Float32, M, l)
    XΩ = zeros(Float32, N, l) # CSC
    XmeanΩ = zeros(Float32, N, l)
    Y = zeros(Float32, N, l) # CSC
    B = zeros(Float32, l, M)
    QtX = zeros(Float32, l, M)
    QtXmean = zeros(Float32, l, M)
    Scores = zeros(Float32, M, dim)
    lasti = 0
    if N > chunksize
        lasti = fld(N, chunksize)+1
    else
        lasti = 1
    end

    # If not 0 the calculation is converged
    # Each epoch s
    println("Random Projection : Y = A Ω")
    for i in 1:lasti
        startp = Int64((i-1)*chunksize+1)
        endp = Int64(i*chunksize)
        if N - endp + chunksize < chunksize
            endp = N
        end
        println("loadchromium")
        X = loadchromium(tenxfile, group, idp, startp, endp, M, perm)
        println("tenxnormalizex")
        X = tenxnormalizex(X, scale)
        println("X*Ω")
        XΩ[startp:endp,:] .= X*Ω
        # Slow
        println("Xmean*Ω")
        for n in startp:endp
            XmeanΩ[n,:] .= sum(rowmeanvec[n].*Ω, dims=1)[1,:]
        end
    end
    println("XΩ - XmeanΩ")
    Y .= XΩ .- XmeanΩ

    # LU factorization
    println("LU factorization : L = lu(Y)")
    F = lu!(Y) # Dense

    for i in 1:niter
        println("##### "*string(i)*" / "*string(niter)*" niter #####")
        # Temporal matrix
        XL = zeros(Float32, M, l) # CSR
        XmeanL = zeros(Float32, M, l) # Dense
        AtL = zeros(Float32, M, l) # CSR
        XAtL = zeros(Float32, N, l) # CSC
        XmeanAtL = zeros(Float32, N, l) # Dense

        println("Normalized power iterations (1/3) : A' L")
        for j in 1:lasti
            startp = Int64((j-1)*chunksize+1)
            endp = Int64(j*chunksize)
            if N - endp + chunksize < chunksize
                endp = N
            end
            println("loadchromium")
            X = loadchromium(tenxfile, group, idp, startp, endp, M, perm)
            println("tenxnormalizex")
            X = tenxnormalizex(X, scale)
            println("X'*F.L")
            XL .+= X'*F.L[startp:endp,:]
            println("XmeanL .+ rowmeanvec' * F.L")
            XmeanL .= XmeanL .+ rowmeanvec' * F.L
        end
        AtL .= XL .- XmeanL # M*l

        println("Normalized power iterations (2/3) : A A' L")
        for j in 1:lasti
            startp = Int64((j-1)*chunksize+1)
            endp = Int64(j*chunksize)
            if N - endp + chunksize < chunksize
                endp = N
            end
            println("loadchromium")
            X = loadchromium(tenxfile, group, idp, startp, endp, M, perm)
            println("tenxnormalizex")
            X = tenxnormalizex(X, scale)
            println("X * AtL")
            XAtL[startp:endp,:] .= X * AtL
            # Slow
            println("rowmeanvec * AtL[m,:]'")
            for n = startp:endp
                XmeanAtL[n,:] .= sum(rowmeanvec[n].*AtL, dims=1)[1,:]
            end
        end
        println("XAtL .- XmeanAtL")
        Y .= XAtL .- XmeanAtL

        if i < niter
            println("Normalized power iterations (3/3) : L = lu(A A' L)")
            # Renormalize with LU factorization
            F = lu!(Y)
        else
            println("QR factorization  (3/3) : Q = qr(A A' L)")
            # Renormalize with QR factorization
            F = qr!(Y)
        end
    end

    println("Calculation of small matrix : B = Q' A")
    Q = Matrix(F.Q) # N * l
    for j in 1:lasti
        startp = Int64((j-1)*chunksize+1)
        endp = Int64(j*chunksize)
        if N - endp + chunksize < chunksize
            endp = N
        end
        println("loadchromium")
        X = loadchromium(tenxfile, group, idp, startp, endp, M, perm)
        println("tenxnormalizex")
        X = tenxnormalizex(X, scale)
        println("(X' * Q[startp:endp,:])'")
        QtX .+= (X' * Q[startp:endp,:])'
        println("QtXmean .+ Q'*rowmeanvec")
        QtXmean .= QtXmean .+ Q'*rowmeanvec
    end
    println("B")
    B = QtX .- QtXmean

    # SVD with small matrix
    println("SVD with small matrix : svd(B)")
    W, λ, V = svd(B)
    U = Q*W
    # PC scores, Explained Variance
    for n = 1:dim
        Scores[:, n] .= λ[n] .* V[:, n]
    end
    ExpVar = sum(λ) / TotalVar
    # Return
    return (V[:,1:dim], λ[1:dim], U[:,1:dim], Scores[:,1:dim], ExpVar, TotalVar)
end