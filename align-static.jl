# This file is part of Jlsca, license is GPLv3, see https://www.gnu.org/licenses/gpl-3.0.en.html
#
# Author: Cees-Bart Breunesse

export CorrelationAlignNaive,CorrelationAlignFFT,correlationAlign

type CorrelationAlignNaive
  reference::Vector
  referenceOffset::Int
  maxShift::Int

  function CorrelationAlignNaive(reference, referenceOffset, maxShift)
    new(reference, referenceOffset, maxShift)
  end
end

type CorrelationAlignFFT
  reversereference0mean::Vector
  referenceOffset::Int
  maxShift::Int
  square_sum_x2::Float64
  sums_y::Nullable{Vector{Float64}}
  sums_y2::Nullable{Vector{Float64}}
  plans::Tuple{Ref{Base.DFT.Plan}, Ref{Base.DFT.Plan}}

  function CorrelationAlignFFT(reference::Vector, referenceOffset::Int, maxShift::Int)
    referenceOffset >= 0 || throw(ErrorException("no negative referenceOffset"))
    maxShift >= 0 || throw(ErrorException("no negative maxShift"))
    reference0mean = reference - mean(reference)
    reversereference0mean = reverse(reference0mean)
    square_sum_x2 = sqrt(sum(reference0mean .^ 2))
    plans::Tuple{Ref{Base.DFT.Plan}, Ref{Base.DFT.Plan}} = (Ref{Base.DFT.Plan}(),Ref{Base.DFT.Plan}())

    new(reversereference0mean, referenceOffset, maxShift, square_sum_x2, Nullable(), Nullable(), plans)
  end

end

# naive O(n^2) implementation
function correlationAlign(samples::Vector, state::CorrelationAlignNaive)
  align::Int = 0
  maxCorr::Float64 = 0

  reference::Vector = state.reference
  referenceOffset::Int = state.referenceOffset
  maxShift::Int = state.maxShift

  window = max(1, referenceOffset - maxShift):(min(referenceOffset + maxShift + length(reference), length(samples)) - length(reference) + 1)

  for o in window
    e = o + length(reference) - 1
    corr = cor(samples[o:e], reference)
    if corr > maxCorr
      maxCorr = corr
      align = o
    end
  end

  ret = (referenceOffset-align,maxCorr)
  return ret
end

function myconv{T<:Base.LinAlg.BlasFloat}(u::StridedVector{T}, v::StridedVector{T}, plans::Tuple{Ref{Base.DFT.Plan}, Ref{Base.DFT.Plan}})
    nu = length(u)
    nv = length(v)
    n = nu + nv - 1
    np2 = n > 1024 ? nextprod([2,3,5], n) : nextpow2(n)
    upad = [u; zeros(T, np2 - nu)]
    vpad = [v; zeros(T, np2 - nv)]
    if T <: Real
      if !isdefined(plans[1], :x)
        plans[1].x = plan_rfft(upad)
      end

      upad_f = plans[1].x * upad
      vpad_f = plans[1].x * vpad
      dotp = upad_f .* vpad_f

      if !isdefined(plans[2], :x)
        plans[2].x = plan_irfft(dotp, np2)
      end
      y = plans[2].x * dotp
    else
        throw(ErrorException("don't"))
    end
    return y[1:n]
end

# http://scribblethink.org/Work/nvisionInterface/nip.html (thx Jasper van Woudenberg)
function correlationAlign(samples::Vector, state::CorrelationAlignFFT)
  align::Int = 0
  maxCorr::Float64 = 0

  reversereference0mean::Vector = state.reversereference0mean
  n = length(reversereference0mean)
  referenceOffset::Int = state.referenceOffset
  maxShift::Int = state.maxShift
  square_sum_x2::Float64 = state.square_sum_x2
  plans::Tuple{Ref{Base.DFT.Plan}, Ref{Base.DFT.Plan}} = state.plans
  window = max(1, referenceOffset - maxShift):(min(referenceOffset + maxShift + n, length(samples)))

  if isnull(state.sums_y)
    state.sums_y = Nullable(zeros(Float64, length(window)+1))
    state.sums_y2 = Nullable(zeros(Float64, length(window)+1))
  end

  sums_y = get(state.sums_y)
  sums_y2 = get(state.sums_y2)

  # compute convolution (sums of squares between ref and samples)
  cv = myconv(reversereference0mean, float(samples[window]), plans)

  # pre-compute the sums and sums of squares of samples
  idx = 2
  for i in window
    s::Float64 = samples[i]
    sums_y[idx] = sums_y[idx-1] + s
    sums_y2[idx] = sums_y2[idx-1] + (s ^ 2)
    idx += 1
  end

  # compute pearson's correlation
  for i in 1:(length(window)-n+1)
    sum_x_y = cv[n+i-1]
    sum_y2 = sums_y2[i+n] - sums_y2[i]
    sum_y = sums_y[i+n] - sums_y[i]
    argh = sum_y2 - (sum_y ^ 2)/n
    r::Float64 = 0
    if argh > 0
      r = sum_x_y / (square_sum_x2 * sqrt(argh))
    end

    if r > maxCorr
      maxCorr = r
      align = window[i]
    end
  end

  ret = (referenceOffset-align,maxCorr)
  return ret
end
