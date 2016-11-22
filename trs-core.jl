# This file is part of Jlsca, license is GPLv3, see https://www.gnu.org/licenses/gpl-3.0.en.html
#
# Author: Cees-Bart Breunesse

abstract Trace

import Base.length, Base.getindex
import Conditional.add
import Conditional.get
import Base.reset
using ProgressMeter
import Base.start, Base.done, Base.next


export Trace,readAllTraces,addSamplePass,popSamplePass,addDataPass,setPostProcessor,popDataPass,hasPostProcessor,reset,getCounter
export start,done,next,endof

# overloading these to implement an iterator
start(trs::Trace) = 1
done(trs::Trace, idx) = pipe(trs) ? false : (idx > length(trs))
next(trs::Trace, idx) = (trs[idx], idx+1)
endof(trs::Trace) = length(trs)

# gets a single trace from a list of traces, runs all the data and sample passes, adds it through the post processor, and returns the result
function getindex(trs::Trace, idx)
  (data, trace) = readTrace(trs, idx)

   # run all the passes over the trace
  for fn in trs.passes
    trace = fn(trace)
    if trace == nothing
      (data,trace) = (nothing,nothing)
      break
    end
  end

  if trace != nothing
    # run all the passes over the data
    for fn in trs.dataPasses
      data = fn(data)
      if data == nothing
        (data, trace) = (nothing,nothing)
        break
      end
    end
  end

  # add it to post processing (i.e conditional averaging) if present
  if data != nothing && trace != nothing && trs.postProcType != Union
    if trs.postProcInstance == Union
      if trs.postProcArguments != nothing
        # trs.postProcInstance = call(trs.postProcType, length(data), length(trace), trs.postProcArguments)
        trs.postProcInstance = trs.postProcType(length(data), length(trace), trs.postProcArguments)
      else
        # trs.postProcInstance = call(trs.postProcType, length(data), length(trace))
        trs.postProcInstance = trs.postProcType(length(data), length(trace))
      end
    end
    add(trs.postProcInstance, data, trace)
  end

  return (data, trace)
end


# add a sample pass (just a Function over a Vector{FLoat64}) to the list of passes for this trace set
function addSamplePass(trs::Trace, f::Function, prprnd=false)
  if prprnd == true
    trs.passes = vcat(f, trs.passes)
  else
    trs.passes = vcat(trs.passes, f)
  end
end

# removes a sample pass
function popSamplePass(trs::Trace, fromStart=false)
  if fromStart
    trs.passes = trs.passes[2:end]
  else
    trs.passes = trs.passes[1:end-1]
  end
end

# add a data pass (just a Function over a Vector{x} where x is the type of the trace set)
function addDataPass(trs::Trace, f::Function, prprnd=false)
  if prprnd == true
    trs.dataPasses = vcat(f, trs.dataPasses)
  else
    trs.dataPasses = vcat(trs.dataPasses, f)
  end
end

# removes a data pass
function popDataPass(trs::Trace, fromStart=false)
  if fromStart
    trs.dataPasses = trs.dataPasses[2:end]
  else
    trs.dataPasses = trs.dataPasses[1:end-1]
  end
end

# removes the data processor and sets the number of traces it fed into the post processor to 0.
function reset(trs::Trace)
  trs.postProcInstance = Union
  trs.tracesReturned = 0
end

# returns the number of traces it fed into the post processor
function getCounter(trs::Trace)
  return trs.tracesReturned
end

# set a post processor that aggregates all data and samples: think conditional averaging.
function setPostProcessor(trs::Trace, x, args=nothing)
  trs.postProcType = x
  trs.postProcArguments = args
end

# returns true when a post processor is set to this trace set
function hasPostProcessor(trs::Trace)
  return trs.postProcType != Union
end

# read all the traces and return them or, more likely, the post processed result (i.e the conditionally averaged result)
function readAllTraces(trs::Trace, traceOffset=start(trs), traceLength=length(trs))
  numberOfTraces = length(trs)
  readCount = 0
  samples = nothing
  datas = nothing
  once = true
  eof = false
  local data, sample, dataLength, sampleLength

  if !pipe(trs)
    progress = Progress(traceLength-1, 1, "Reading traces.. ")
  end

  for idx in traceOffset:(traceOffset + traceLength - 1)
    try
      (data, sample) = trs[idx]
    catch e
      if isa(e, EOFError)
        @printf("EOF after reading %d traces ..\n", readCount)
        eof = true
        break
      else
        throw(e)
      end
    end

    # next trace if a pass ditched this trace
    if data == nothing || sample == nothing
      continue
    end


    if once && verbose
      once = false
      @printf("Input traces (after %d data and %d sample passes):\n", length(trs.dataPasses), length(trs.passes))
      if !pipe(trs)
        @printf("traces:    %d:%d\n", traceOffset, traceOffset+traceLength-1)
      end
      @printf("#samples:  %d\n", length(sample))
      @printf("#data:     %d\n", length(data))
      @printf("post proc: %s\n", trs.postProcType == Union ? "none" : string(trs.postProcType))
      @printf("\n")
    end

    if trs.postProcType == Union
      # no post processor

      if samples == nothing || datas == nothing
          # first time, so allocate
          sampleLength = length(sample)
          dataLength = length(data)
          samples = Vector{eltype(sample)}(sampleLength * traceLength)
          datas = Vector{eltype(data)}(dataLength * traceLength)
      end

      samples[readCount*sampleLength+1:readCount*sampleLength+sampleLength] = sample
      datas[readCount*dataLength+1:readCount*dataLength+dataLength] = data
    end

    # valid trace, bump read counter
    readCount += 1

    if !pipe(trs)
      update!(progress, idx)
    end
  end

  trs.tracesReturned += readCount

  if trs.postProcType != Union
    # return the post processing result
    (datas, samples) = get(trs.postProcInstance)
    return (datas, samples, eof)
  else
    # resize & reshape that shit depending on the readCount
    resize!(datas, (dataLength*readCount))
    resize!(samples, (sampleLength*readCount))

    datas = reshape(datas, (dataLength, readCount))'
    samples = reshape(samples, (sampleLength, readCount))'

    return (datas,samples, eof)
  end
end
