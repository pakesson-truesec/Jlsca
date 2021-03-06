module Trs

abstract PostProcessor

export PostProcessor
export getData,getSamples,writeData,writeSamples

include("conditional.jl")

include("trs-core.jl")
include("trs-distributed.jl")
include("trs-inspector.jl")
include("trs-inspector-mmap.jl")
include("trs-splitbinary.jl")

include("distributed.jl")
include("conditional-average.jl")
include("conditional-bitwisereduction.jl")
include("incremental-correlation.jl")

end
