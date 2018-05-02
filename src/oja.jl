"""
    oja(;input="", output=".", logscale=true, pseudocount=1, rowmeanlist="", colsumlist="", masklist="", dim=3, stepsize=0.1, numepoch=5, scheduling="robbins-monro", g=0.9, epsilon=1.0e-8, logfile=false)

Online PCA solved by stochastic gradient descent method, also known as Oja's method.

Input Arguments
---------
- `input` : Julia Binary file generated by `OnlinePCA.csv2sl` function.
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
- `logfile` : Whether the intermediate files are saved, in every 1000 iteration.

Output Arguments
---------
- `W` : Eigen vectors of covariance matrix (No. columns of the data matrix × dim)
- `λ` : Eigen values (dim × dim)
- `V` : Loading vectors of covariance matrix (No. rows of the data matrix × dim)

Reference
---------
- SGD-PCA（Oja's method) : [Erkki Oja et. al., 1985](https://www.sciencedirect.com/science/article/pii/0022247X85901313), [Erkki Oja, 1992](https://www.sciencedirect.com/science/article/pii/S0893608005800899)
"""
function oja(;input="", output=".", logscale=true, pseudocount=1, rowmeanlist="", colsumlist="", masklist="", dim=3, stepsize=0.1, numepoch=5, scheduling="robbins-monro", g=0.9, epsilon=1.0e-8, logfile=true)
    # Initialization
    N, M = init(input) # No.gene, No.cell
    W = zeros(Float32, M, dim) # Eigen vectors
    v = zeros(Float32, M, dim) # Temporal Vector (Same length as x)
    D = Diagonal(reverse(1:dim)) # Diagonaml Matrix
    for i=1:dim
        W[i,i] = 1
    end

    # mean (gene), library size (cell), cell mask list
    meanvec = zeros(Float32, N, 1)
    libvec = zeros(Float32, M, 1)
    cellmaskvec = zeros(Float32, M, 1)
    if rowmeanlist != ""
        meanvec = readcsv(rowmeanlist, Float32)
    end
    if colsumlist != ""
        libvec = readcsv(colsumlist, Float32)
    end
    if masklist != ""
        cellmaskvec = readcsv(masklist, Float32)
    end

    # directory for log file
    if typeof(logfile) == String
        if(!isdir(logfile))
            mkdir(logfile)
        end
    end

    # progress
    progress = Progress(numepoch)
    for s = 1:numepoch
        open(input) do file
            N = read(file, Int64)
            M = read(file, Int64)
            for n = 1:N
                # Data Import
                x = deserialize(file)
                if logscale
                    x = log10.(x + pseudocount)
                end
                if masklist != ""
                    x = x[cellmaskvec]
                end
                if (rowmeanlist != "") && (colsumlist != "")
                    x = (x - meanvec[n, 1]) ./ libvec
                end
                if (rowmeanlist != "") && (colsumlist == "")
                    x = x - meanvec[n, 1]
                end
                if (rowmeanlist == "") && (colsumlist != "")
                    x = x ./ libvec
                end
                # SGD × Robbins-Monro
                if scheduling == "robbins-monro"
                    W .= W .+ ∇fn(W, x, D * Float32(stepsize)/(N*(s-1)+n), M)
                # SGD × Momentum
                elseif scheduling == "momentum"
                    v .= g .* v .+ ∇fn(W, x, D * Float32(stepsize), M)
                    W .= W .+ v
                # SGD × NAG
                elseif scheduling == "nag"
                    v = g .* v + ∇fn(W - g .* v, x, D * Float32(stepsize), M)
                    W .= W .+ v
                # SGD × Adagrad
                elseif scheduling == "adagrad"
                    grad = ∇fn(W, x, D * Float32(stepsize), M)
                    grad = grad / Float32(stepsize)
                    v .= v .+ grad .* grad
                    W .= W .+ Float32(stepsize) ./ (sqrt.(v) + epsilon) .* grad
                else
                    error("Specify the scheduling as robbins-monro, momentum, nag or adagrad")
                end
                # NaN
                if any(isnan, W)
                    error("NaN values are generated. Select other stepsize")
                end

                # Retraction
                W .= full(qrfact!(W)[:Q], thin=true)
                # save log file
                if logfile
                     if(mod((N*(s-1)+n), 1000) == 0)
                        writecsv(logfile * "/W_" * string((N*(s-1)+n)) * ".csv", W)
                        writecsv(logfile * "/RecError_" * string((N*(s-1)+n)) * ".csv", RecError(W, input))
                        touch(logfile * "/W_" * string((N*(s-1)+n)) * ".csv")
                        touch(logfile * "/RecError_" * string((N*(s-1)+n)) * ".csv")
                    end
                end
            end
        end
        next!(progress)
    end
    # Return, W, λ, V
    WλV(W, input, dim)
end